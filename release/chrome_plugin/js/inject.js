setTimeout(function(){
  var inject;
  inject = function(name, callback) {
    var s;
    s = document.createElement('script');
    s.src = chrome.extension.getURL('js/' + name);
    s.onload = callback || function() {};
    return document.head.appendChild(s);
  };
  inject('renren-markdown.chrome.js');
  receiveMessage = function(event)
  { 
    if (event.origin !== "http://blog.renren.com")
      return;
    xmlHttp=new XMLHttpRequest();
    xmlHttp.open("GET", event.data, false);
    xmlHttp.send(null);
    window.frames[1].postMessage(xmlHttp.responseText,"*");
  };
  window.frames[0].addEventListener("message", receiveMessage, false);
},5000);


