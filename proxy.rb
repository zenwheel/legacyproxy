#!/usr/bin/env ruby

require 'rubygems'
require 'socket'
require 'uri'
require 'net/http'
require 'net/https'
require 'openssl'
require 'nokogiri'
require 'htmlentities'
require 'rmagick'

$port = 8080
$bufferLength = 4096
$verbose = false
$userAgent = 'LegacyProxy/1.0'

$verbose = true if ARGV.include?('-v') or ARGV.include?('--verbose')

$entityCoder = HTMLEntities.new

$statusCodes = {
	100 => "Continue",
	101 => "Switching Protocols",
	200 => "OK",
	201 => "Created",
	202 => "Accepted",
	203 => "Non-Authoritative Information",
	204 => "No Content",
	205 => "Reset Content",
	206 => "Partial Content",
	300 => "Multiple Choices",
	301 => "Moved Permanently",
	302 => "Found",
	303 => "See Other",
	304 => "Not Modified",
	307 => "Temporary Redirect",
	308 => "Permanent Redirect",
	400 => "Bad Request",
	401 => "Unauthorized",
	403 => "Forbidden",
	404 => "Not Found",
	405 => "Method Not Allowed",
	406 => "Not Acceptable",
	407 => "Proxy Authentication Required",
	408 => "Request Timeout",
	409 => "Conflict",
	410 => "Gone",
	411 => "Length Required",
	412 => "Precondition Failed",
	413 => "Payload Too Large",
	414 => "URI Too Long",
	415 => "Unsupported Media Type",
	416 => "Range Not Satisfiable",
	417 => "Expectation Failed",
	426 => "Upgrade Required",
	428 => "Precondition Required",
	429 => "Too Many Requests",
	431 => "Request Header Fields Too Large",
	451 => "Unavailable For Legal Reasons",
	500 => "Internal Server Error",
	501 => "Not Implemented",
	502 => "Bad Gateway",
	503 => "Service Unavailable",
	504 => "Gateway Timeout",
	505 => "HTTP Version Not Supported",
	511 => "Network Authentication Required"
}

server = TCPServer.open($port)
puts "Listening on #{$port}, press ^C to exit..."

def sanitizeHtml(doc, requestHeaders)
	parsedDoc = Nokogiri::HTML(doc)

	# rewrite https urls to http
	parsedDoc.css("img").each do |image|
		image['src'] = image['src'].sub(/^https:/, 'http:') if image['src'].nil? == false
	end
	parsedDoc.css("a").each do |link|
		link['href'] = link['href'].sub(/^https:/, 'http:') if link['href'].nil? == false
	end

	if requestHeaders.nil? == false && requestHeaders['user-agent'] == 'Mozilla/1.0N (Macintosh)' then
		parsedDoc.css("tr").each do |tr|
			br = Nokogiri::XML::Node.new("br", parsedDoc)
			tr.add_next_sibling(br)
		end
	end
	parsedDoc.css("script").each { |s| s.remove }
	parsedDoc.css("noscript").each { |s| s.remove }
	parsedDoc.css("style").each { |s| s.remove }

	html = parsedDoc.to_html(encoding: 'US-ASCII') # force entity encoding so they survive transit, otherwise nokogiri will output the real characters which get lost
	html = html.gsub(/&#\d+;/) { |s| $entityCoder.encode($entityCoder.decode(s), :decimal) } # repair entities

	if requestHeaders.nil? == false && requestHeaders['user-agent'] == 'Mozilla/1.0N (Macintosh)' then
		# replace some fancy characters with simple versions
		html = html.gsub('&#160;', " ")
		html = html.gsub('&#8211;', "-")
		html = html.gsub('&#8212;', "-")
		html = html.gsub('&#8216;', "'")
		html = html.gsub('&#8217;', "'")
		html = html.gsub('&#8220;', "\"")
		html = html.gsub('&#8221;', "\"")
		html = html.gsub('&#8230;', "...")
		html = html.gsub('&#188;', "1/4")
		html = html.gsub('&#189;', "1/2")
		html = html.gsub('&#190;', "3/4")
	end

	html
end

def sendResponse(client, code, headers = {}, body = nil, requestHeaders = nil)
	message = '-'
	message = $statusCodes[code.to_i] if $statusCodes.has_key?(code.to_i)

	headers['cache-control'] = 'no-cache'
	headers['connection'] = 'close'
	headers['date'] = Time.now.utc.strftime '%a, %d %b %Y %H:%M:%S GMT'
	headers['server'] = $userAgent

	headers['content-type'] = 'text/plain' if headers.has_key?('content-type') == false # ensure content type

	# tweak html content type
	if headers['content-type'] =~ /^text\/html/ then
 		body.force_encoding($1) if body.nil? == false && headers['content-type'] =~ /; charset=(.*)$/
		headers['content-type'] = 'text/html'
 	end

	if headers['content-type'] =~ /^image\/svg/ || headers['content-type'] =~ /^image\/png/ then
		# pre-render unsupported images, rewrite to gif (it's small and preserves transparency)
		headers['content-type'] = 'image/gif'
		img = Magick::Image.from_blob(body).first
		img.format = 'gif'
		body = img.to_blob
	else
		body = sanitizeHtml(body, requestHeaders) if headers['content-type'] == 'text/html' && body.nil? == false
	end

	headers['content-length'] = body.bytesize.to_s if body.nil? == false # update content length

	client.print "HTTP/1.0 #{code} #{message}\r\n"
	headers.each do |k, v|
		key = k.to_s.split(/-/).map { |s| s.capitalize }.join('-')
		client.print "#{key}: #{v}\r\n"
	end
	client.print "\r\n"
	client.write body if body.nil? == false
	client.close
end

def sendError(client, message)
	response = "<html>\n<head>\n<title>Proxy Error</title>\n</head>\n\n<body>\n#{message}\n</body>"
	sendResponse(client, 503, { "Content-Type" => "text/html" }, response)
end

def sendProxyContent(client, url, verb, headers, body)
	begin
		# TODO: try https first, fall back to http?
		if url.start_with?('http') == false then
			if url =~ /:443/ then
				url = "https://#{url.strip}"
			else
				url = "http://#{url.strip}"
			end
		end

		uri = URI.parse(url.strip)
		puts "<-- #{uri.to_s}" if $verbose
		http = Net::HTTP.new(uri.host, uri.port)
		if uri.scheme == 'https' then
			http.use_ssl = true
			http.verify_mode = OpenSSL::SSL::VERIFY_NONE
		end
		http.open_timeout = 30
		http.read_timeout = 45

		response = http.send_request(verb, uri.path.nil? || uri.path.empty? ? "/" : uri.path, body, headers)

		puts "--> Response code: #{response.code}" if $verbose

		responseHeaders = {}
		response.header.each do |key, value|
			next if value.nil?
			key = key.downcase
			if responseHeaders.has_key?(key) then
				responseHeaders[key] += ", #{value}"
			else
				responseHeaders[key] = value
			end
		end
		puts "--> Response Headers: #{responseHeaders}" if $verbose

		case response
		when Net::HTTPRedirection then
			sendProxyContent(client, response.header['location'], verb, headers, body)
		else
			sendResponse(client, response.code, responseHeaders, response.body, headers)
		end
	rescue Interrupt
		sendError(client, "Interrupt")
	rescue => e
		sendError(client, "#{e}")
		$stderr.puts "Error: #{e}"
	end
end

loop {
	Thread.start(server.accept) do |client|
		clientAddress = client.peeraddr
		request = ""

		while client.closed? == false do
			read_ready = IO.select([client])[0]
			if read_ready.include?(client)
				data = client.recv_nonblock($bufferLength)
				request += data
				break if data.bytesize < $bufferLength
			end
		end

		requestHeaders, body = request.split("\r\n\r\n", 2)
		body = nil if body.length == 0
		headers = {}
		urlRequest = nil
		requestHeaders.split("\r\n").each do |h|
			# first line is the GET <url> HTTP/<version> request:
			if urlRequest.nil? then
				urlRequest = h.split(/\s+/)
				next
			end
			key, value = h.split(/:\s*/)
			next if value.nil?
			key = key.downcase
			if headers.has_key?(key) then
				headers[key] += ", #{value}"
			else
				headers[key] = value
			end
		end

		headers['x-forwarded-for'] = clientAddress[3]
		headers['via'] = "HTTP/1.1 #{$userAgent}"

		if urlRequest.length != 3 then
			sendError(client, "Invalid request")
			return
		end
		verb = urlRequest[0]
		url = urlRequest[1]

		puts "--> #{clientAddress[2]}:#{clientAddress[1]} #{verb} #{url}"

 		puts "Request Headers: '#{headers}'" if $verbose
 		puts "Request Body: '#{body}'" if $verbose && body.nil? == false
		sendProxyContent(client, url, verb, headers, body)
	end
}
