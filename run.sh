iced -I inline  -c renren-markdown.chrome.iced
cp -f _include.js release/chrome_plugin/js/renren-markdown.chrome.js
cat renren-markdown.chrome.js>>release/chrome_plugin/js/renren-markdown.chrome.js
iced -I inline  -c renren-markdown.user.iced
cp -f _include.js release/renren-markdown.user.js
cat renren-markdown.chrome.js>>release/renren-markdown.user.js


