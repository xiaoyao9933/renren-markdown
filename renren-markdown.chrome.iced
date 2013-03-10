`
// vim: nowrap
// Copyright (c) 2013, smilekzs. (MIT Licensed)
// ==UserScript==
// @name          renren-markdown
// @namespace     http://github.com/smilekzs
// @version       0.4.32
// @description   write well-formatted blogs on renren.com with markdown
// @include       *blog.renren.com/blog/*Blog*
// @include       *blog.renren.com/blog/*edit*
// @include       *blog.renren.com/*Entry*
// ==/UserScript==

//#include
`

# utilities

# trigger => delay => callback
# more triggers before callback => only last trigger is kept
# callback returns non-null => retry after original delay
W=window
class DelayTrigger
  constructor: (cb)->
    @cb=cb
    @tid=null
  trigger: (delay)->
    if @tid? then clearTimeout @tid
    @tid=setTimeout (=>if @cb()? then @trigger(delay)), delay


# module inlinify {

# adapted from: http://stackoverflow.com/questions/298750/how-do-i-select-text-nodes-with-jquery
getTextNodesIn=(node)->
  textNodes = []
  getTextNodes=(node)->
    if node.nodeType == 3
      textNodes.push(node)
    else
      for n in node.childNodes
        getTextNodes(n)
    null
  getTextNodes(node)
  return textNodes

# get css rules from css text
getCssRules=(css)->
  doc=JQ('<iframe />').css('display', 'none').appendTo('body')[0].contentDocument
  JQ(doc).find('head').append("<style>#{css}</style>")
  doc.styleSheets[0].cssRules

# escape cssText to avoid single-double-quote hell
escapeCssText=(cssText)->
  cssText.replace /"/g, "'"

# inline css with specificity awareness
getSpec=(x)->
  SPECIFICITY.calculate(x)[0].specificity.split(',').map(Number)

cmp=(a, b)->
  switch
    when a<b then -1
    when a>b then +1
    else 0

cmpSpec=(a, b)->
  for i in [0...4]
    if (c=cmp(a[i], b[i])) then return c
  return 0

arrayize=(a)->[].slice.call(a)
inlineCss=(root, rules)->
  arrayize(rules).forEach (r)->
    sel=r.selectorText
    spec=getSpec(sel)
    if (selected=root.querySelectorAll(sel))?
      arrayize(selected).forEach (el)->
        if !el.stylePlus?
          el.stylePlus={}
        for key in (style=r.style)
          value=style.getPropertyValue(key) 
          unless (orig=el.stylePlus[key])? && cmpSpec(orig.spec, spec)>0
            el.stylePlus[key]={spec, value}
        null
  arrayize(root.querySelectorAll('*')).forEach (el)->
    if el.stylePlus?
      for key in el.style
        el.stylePlus[key]=el.style.getPropertyValue(key)
      for k, p of el.stylePlus
        # dirty workaround: firefox `padding-right-value` problem
        if k.match(/-value$/) && k!='drop-initial-value'
          k=k[0...(k.lastIndexOf('-'))]
        el.style.setProperty(k, p.value, 'important')
      delete el.stylePlus
      null
  root

# convert everything within `el` into <span>
spanifyAll=(el)->
  jel=JQ(el)

  # clone `el` with raw span element
  # also prevent elements with no text from being stripped
  spanify=(el)->
    if !el? then return JQ('<span />')
    style=escapeCssText el.style.cssText
    cont=el.innerHTML.trim() || '<span style="display: none;">&nbsp;</span>'
    JQ("""<span style="#{style}">#{cont}</span>""")

  # preformatted text: replace with `&amp;` and friends
  jel.find('pre').each ->
    for text in getTextNodesIn(this)
      str=text.data.toString()
        .replace(/\&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/\ /g, '&nbsp;')
        .replace(/[\n\r\v]/g, '<br/>')
      JQ(text).replaceWith("<span>#{str}</span>")
    #this.style.whiteSpace='pre'

  # workaround for td over-shrinking
  jel.find('td').children().each ->
    this.style.whiteSpace||='nowrap'

  # flatten table (strips t{head, body, foot})
  jel.find('tbody, thead, tfoot').children().unwrap()

  # container -> span with corresponding `display: xxx`
  # NOTE: order of operation is significant!
  [
    ['pre, code', 'inline']
    ['s, del', 'inline']
    ['div, p, blockquote, q, article', 'block']
    ['h1, h2, h3, h4, h5, h6', 'block']
    ['hr', 'block']
    ['td, th', 'table-cell'] # table family
    ['tr', 'table-row']
    ['table', 'table']
  ].forEach (arg)->
    ((tag, disp)->
      while x=jel.find(tag)[0]
        s=spanify(x)
        s[0].style.display||=disp
        JQ(x).replaceWith(s)
      return
    )(arg...)
    return

  # tags using internal span for style
  ['a'].forEach (tag)->
    jel.find(tag).each ->
      st=this.style.cssText
      this.style.cssText=''
      JQ(this).wrap("""<span style="#{escapeCssText st}"/>""")

  jel


# } //module inlinify
messagedata=""
receiveMessage=(event)->
  console.log("received data")
  messagedata=event.data

checkMessageReady=(cb)->
  mid=setInterval (->
    console.log(messagedata)
    if messagedata isnt ""
      clearInterval(mid)
      cb()
  ) ,1000

# module getGist {

getGist=(id, cb)->
  gistJsRes=null
  W.frames[0].postMessage("https://gist.github.com/#{id}.js","*")
  await checkMessageReady defer()
  gistJs=messagedata
  messagedata=""
  console.log("jumped")
  cssUrl=gistJs.match(/link href=\\"([^"]*)\\"/)?[1]
  if !cssUrl
    err=Error("can't find gist css")
    cb err; throw err

  gistCssRes=null
  W.frames[0].postMessage(cssUrl,"*")
  await checkMessageReady defer()
  gistCss=messagedata
  messagedata=""

  i1=gistJs.indexOf("\n")
  i1=gistJs.indexOf("('", i1)+2
  i2=gistJs.lastIndexOf("')")

  if i1>0 && i2>0
    gistHtml=JSON.parse('\"'+gistJs.substring(i1, i2).replace(/\\'/g, '\'')+'\"')
  else
    err=Error("can't find gist content")
    cb err; throw err

  cb(null, gistCss, gistHtml)


# } //module getGist

# module rrmd {

# encode & embed markdown source into generated html

str_to_b64=(str)->W.btoa unescape encodeURIComponent str
b64_to_str=(b64)->decodeURIComponent escape W.atob b64

embed=(h, md)->
  h+"""<span style="visibility: hidden; display: block; height: 0; background-image: url('http://dummy/$rrmd$')">#{str_to_b64(md)}</span>"""

unembed=(h)->
  list=JQ(h).find('span').filter(->this.style.backgroundImage.match /\$rrmd\$/)
  b64=list[0]?.innerHTML
  if !b64? then b64=''
  try return b64_to_str(b64)
  catch e then return ''


W.rrmd=rrmd=
  lib:
    {JQ, marked, SPECIFICITY}

  options:
    delay: 400
    embedGistQ: true
    emoticonQ: true
    removeAnchorQ: true

  init: ->
    @cssRules=getCssRules(RRMD_STYLE)
    @editor=W.tinymce.editors[0]
    @ui.init()
    @ui.area.val(unembed @editor.getContent())
    @dt=new DelayTrigger =>@update()
    @ui.area.bind 'input', =>
      @dt.trigger(@options.delay) # need to preserve input event even when busy
      if !@busyQ
        @ui.setStatus('...', 'Input...', 0)

    @busyQ=false
    @ui.setStatus('ok', 'Ready.', 0)

  ui:
    html:
      """
      <div id="rrmd_wrapper" style="margin: 0 0 1em 0">
        <textarea id="rrmd_area" style="font-family: Consolas, 'Inconsolata', 'Courier New', 'Monospace';" placeholder="Type markdown _here_!"></textarea>
        <div id="rrmd_status" style="margin: 0.5em 0 0 0;">
          <span id="rrmd_status_icon"></span>
          <span id="rrmd_status_text"></span>
          <span id="rrmd_status_progress" style="float: right;"></span>
          <span style="clear: both;"></span>
          <div style="height: 2px; width: 100%;"><div id="rrmd_status_pb" style="display: none; background-color:#0c0; width: 0%; height: 100%"></div></div>
        </div>
      </div>
      """
    init: ->

      JQ('#editor_tbl').before(@html)
      @area=JQ('#rrmd_area')
      @statusText=JQ('#rrmd_status_text')
      @statusProgress=JQ('#rrmd_status_progress')
      @statusPb=JQ('#rrmd_status_pb')

      # fix "offset blog title input"
      JQ('#title_bg')[0]?.style.cssText='position: inherit !important; width: 100%'
      JQ('#title')[0]?.style.cssText='width: 98%'
      JQ('#editor_ifr')[0]?.contentDocument.body.style.paddingTop="0px"
      

    setStatus: (type, text, progress)->
      console.log(progress + ':' + text)
      # TODO: handle type icon
      if text? then @statusText.html(text)
      if 0<=progress<=1
        p=Math.round(progress*100).toString()+'%'
        @statusProgress.html(p)

        switch progress
          when 0
            @statusPb.stop(true).css('width', 0).hide()
          when 1
            await @statusPb.stop(true).css('opacity', '1').show().animate({width: p}, 500, 'linear', defer())
            await @statusPb.fadeOut(1500, 'swing', defer())
            @statusPb.css('width', 0)
          else
            @statusPb.show().animate({width: p}, 750, 'swing')

  markdown: (md)->
    el=JQ marked md
    if !el.length then return JQ('<span />')
    el=el.wrapAll('<span />').parent()[0]
    spanifyAll inlineCss el, @cssRules

  gistManager:
    saved: {}
    cssRules: null
    get: (id, cb)->
      if @saved[id]? then return cb null, @saved[id]
      err=null; gistCss=''; gistHtml=''
      await getGist id, defer(err, gistCss, gistHtml)
      if err?
        cb err; throw err
      else
        if !@cssRules? then @cssRules=getCssRules(gistCss)
        gistCssRules=@cssRules
        jel=JQ(gistHtml)
        # special: promote markdown content
        jel.find('article.markdown-body').each ->
          inlineCss this, rrmd.cssRules
          inlineCss this, gistCssRules # necessary: for code highlighting
          JQ(this).parentsUntil('div.gist').last().replaceWith(this)
          null
        el=spanifyAll inlineCss jel.wrapAll('<span />').parent()[0], @cssRules
        cb null, @saved[id]=el

  conv: (cb)->
    md=@ui.area.val()
    el=@markdown(md)
    @ui.setStatus(null, null, 0.01)

    if @options.embedGistQ
      re=/^(?:(?:http|https)\:\/\/)?gist\.github\.com\/([\w\/]+)/
      list=el.find('a').toArray().filter (a)->
        re.test(a.href) && a.href==a.innerHTML
      n=list.length
      for a, i in list
        id=a.href.match(re)[1]
        err=null; gist=''
        await @gistManager.get id, defer(err, gist)
        if err?
          cb err; throw err
        JQ(a).replaceWith(gist)
        @ui.setStatus(null, null, 0.01+0.99*(i+1)/n)

    if @options.emoticonQ
      el.find('img[src=""]').each ->
        if (em=EMOTICON[@alt])?
          @src=EMOTICON_ROOT+em.src
          @alt=em.alt

    if @options.removeAnchorQ
      el.find('a[name]').remove()

    hmd=embed(el.wrapAll('<span />').parent().html()||'', md)
    cb null, hmd

  update: ->
    if @busyQ then return false
    @busyQ=true
    @ui.setStatus('wip', 'Converting...', 0)

    err=null; html=''
    await @conv defer(err, html)
    if err?
      @ui.setStatus('err', "Error! #{err.toString()}", null)
      @busyQ=false
      throw err
    @editor.setContent(html)

    @ui.setStatus('ok', 'Conversion complete.', 1)
    @busyQ=false
    null


# init after all modules load

checkPageReady=(cb)->
  tid=setInterval (->
    if W.tinymce?.editors?[0]?
      # && W.MathJax?.isReady
      clearInterval(tid)
      cb()
  ), 1000

await checkPageReady defer()
# await W.MathJax.Hub.Queue [defer()]

rrmd.init()
rrmd.JQ=JQ # for debugger access
messagedata=""
W.frames[1].addEventListener("message", receiveMessage, false);
# } //module rrmd
