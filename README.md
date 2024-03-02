The internet has changed a lot in the past decade or two and has left some of the vintage computers that built it behind.  This is an HTTP proxy that can be used to access modern content on older browsers.

### Security

*Important* This proxy removes all security used in the modern web, never connect to it over the internet, only use it when you can run it on a private, trusted LAN between the legacy computer and the proxy host.

### Installation

I intended to run this on a Raspberry Pi, the installation procedure I used was:

	sudo apt-get install ruby ruby-bundler ruby-dev build-essential patch zlib1g-dev liblzma-dev libmagickwand-dev
	cd legacy-proxy
	bundle install

Then to run the proxy, just start `ruby ./proxy.rb` in a shell.  At this point, the default ruby on Raspberry Pi OS (bookworm) is 3.1.2.

Lastly, on macOS the only weird thing I needed was to `brew install imagemagick@6`, the default `imagemagick` version didn't work with `rmagick`.

### Usage

I built it to work with Netscape 1.0N (maybe it should be named netscapeproxy?).  Due to SSL, CSS, tables and a few other things that have changed on the web, it didn't work very well.  To use the proxy: choose "Preferences..." from the "Options" menu, select "Proxies" from the popup menu at the top.  For the "HTTP Proxy", enter the IP or hostname for the local machine you are running the proxy on, port `8080` then hit "OK".

In the browser you can enter a URL, such as [http://www.apple.com/](http://www.apple.com/), it will make an HTTP request to the proxy to fetch the URL.  The proxy will then request the site, following any redirects, such as HTTP -> HTTPS.  Any errors will be passed along, successful requests will be processed slightly:

* `image/png` and `image/svg` images will be rendered to an `image/gif` before being passed along to the browser.
* The `charset` is removed from the `text/html` MIME type so Netscape will open show the page rather than prompting for a helper to open it.
* Any URLs in `<img src=>` or `<a href=>` tags will be modified so they refer to an HTTP url instead of HTTPS.
* It sticks a `<br>` after each `<tr>...</tr>` so tables look a little better than a big wall of text (Netscape 1.0N only).
* `<style>` and `<script>` tags are removed
* Some HTML common, fancy entities are rewritten as plain text so they show up properly  (Netscape 1.0N only).
* `nokogiri` is used to process the HTML, so any weird things like missing tags will get fixed and passed along.

### Changes

I haven't tried any other old browsers or computers, but hopefully the proxy can be extended to handle other tweaks in the future, please submit PRs if you extend it!
