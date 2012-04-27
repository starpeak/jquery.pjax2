$ = jQuery
# When called on a link, fetches the href with ajax into the
# container specified as the first parameter or with the data-pjax
# attribute on the link itself.
#
# Tries to make sure the back button and ctrl+click work the way
# you"d expect.
#
# Accepts a jQuery ajax options object that may include these
# pjax specific options:
#
# container - Where to stick the response body. Usually a String selector.
#             $(container).html(xhr.responseBody)
#      push - Whether to pushState the URL. Defaults to true (of course).
#   replace - Want to use replaceState instead? That"s cool.
#
# For convenience the first parameter can be either the container or
# the options object.
#
# Returns the jQuery object

$.fn.pjax = (container, options) ->
  @live "click.pjax", (event) ->
    handleClick event, container, options

# Public: pjax on click handler
#
# Exported as $.pjax.click.
#
# event   - "click" jQuery.Event
# options - pjax options
#
# Examples
#
#   $("a").live("click", $.pjax.click)
#   # is the same as
#   $("a").pjax()
#
#  $(document).on("click", "a", function(event) {
#    container = $(this).closest("[data-pjax-container]")
#    return $.pjax.click(event, container)
#  })
#
# Returns false if pjax runs, otherwise nothing.

handleClick = (event, container, options) ->
  options = optionsFor container, options

  link = event.currentTarget

  throw "$.fn.pjax or $.pjax.click requires an anchor element"  if link.tagName.toUpperCase() isnt "A"

  # Middle click, cmd click, and ctrl click should open
  # links in a new tab as normal.
  if event.which > 1 or event.metaKey
    return

  # Ignore cross origin links
  if location.protocol isnt link.protocol or location.host isnt link.host
    return

  # Ignore anchors on the same page
  if link.hash and link.href.replace(link.hash, "") is location.href.replace(location.hash, "")   
    return   

  defaults = 
    url: link.href
    container: $(link).attr("data-pjax")
    target: link
    fragment: null

  $.pjax $.extend({}, defaults, options)

  event.preventDefault()

  return

# Loads a URL with ajax, puts the response body inside a container,
# then pushState()"s the loaded URL.
#
# Works just like $.ajax in that it accepts a jQuery ajax
# settings object (with keys like url, type, data, etc).
#
# Accepts these extra keys:
#
# container - Where to stick the response body.
#             $(container).html(xhr.responseBody)
#      push - Whether to pushState the URL. Defaults to true (of course).
#   replace - Want to use replaceState instead? That"s cool.
#
# Use it just like $.ajax:
#
#   xhr = $.pjax({ url: @href, container: "#main" })
#   console.log( xhr.readyState )
#
# Returns whatever $.ajax returns.

pjax = (options) ->
  fire = (type, args) ->
    event = $.Event type, 
      relatedTarget: target
    context.trigger event, args
    not event.isDefaultPrevented()

  timeoutTimer = null

  options = $.extend true, {}, $.ajaxSettings, pjax.defaults, options

  options.url = options.url() if $.isFunction(options.url)

  target = options.target

  hash = parseURL(options.url).hash

  context = options.context = findContainerFor(options.container)

  # We want the browser to maintain two separate internal caches: one
  # for pjax"d partial page loads and one for normal page loads.
  # Without adding this secret parameter, some browsers will often
  # confuse the two.
  options.data = {} unless options.data
  options.data._pjax = context.selector

  options.beforeSend = (xhr, settings) ->
    if settings.timeout > 0

      timeoutFunction = ->
      
        if fire("pjax:timeout", [xhr, options])
          xhr.abort "timeout"
        return
           
      timeoutTimer = setTimeout(timeoutFunction, settings.timeout)

      # Clear timeout setting so jquerys internal timeout isn't invoked
      settings.timeout = 0

    xhr.setRequestHeader "X-PJAX", "true"
    xhr.setRequestHeader "X-PJAX-Container", context.selector

    return false unless fire("pjax:beforeSend", [xhr, settings])

    if options.push and not options.replace
      # Cache current container element before replacing it
      containerCache.push pjax.state.id, context.clone(true, true).contents()

      window.history.pushState null, "", options.url
    
    fire "pjax:start", [xhr, options]
    fire "pjax:send", [xhr, settings]
    return

  options.complete = (xhr, textStatus) ->
    clearTimeout(timeoutTimer) if (timeoutTimer)

    fire "pjax:complete", [xhr, textStatus, options]
    fire "pjax:end", [xhr, options]
    return

  options.error = (xhr, textStatus, errorThrown) ->
    container = extractContainer "", xhr, options

    allowed = fire "pjax:error", [xhr, textStatus, errorThrown, options]
    window.location = container.url if textStatus isnt "abort" and allowed
    return
  
  options.success = (data, status, xhr) ->
    container = extractContainer data, xhr, options

    unless container.contents
      window.location = container.url
      return

    pjax.state = 
      id: options.id or uniqueId()
      url: container.url
      container: context.selector
      fragment: options.fragment
      timeout: options.timeout
    
    if options.push or options.replace
      window.history.replaceState pjax.state, container.title, container.url

    document.title = container.title if container.title
    context.html container.contents

    # Scroll to top by default
    $(window).scrollTop(options.scrollTo) if typeof options.scrollTo is "number"
   

    # Google Analytics support
    _gaq.push(["_trackPageview"]) if (options.replace or options.push) and window._gaq 
      

    # If the URL has a hash in it, make sure the browser
    # knows to navigate to the hash.
    
    window.location.href = hash if hash isnt ""      

    fire "pjax:success", [data, status, xhr, options]
    return

  # Initialize pjax.state for the initial page load. Assume we"re
  # using the container and options of the link we"re loading for the
  # back button to the initial page. This ensures good back button
  # behavior.
  unless pjax.state
    pjax.state = 
      id: uniqueId()
      url: window.location.href
      container: context.selector
      fragment: options.fragment
      timeout: options.timeout
    
    window.history.replaceState pjax.state, document.title

  # Cancel the current request if we"re already pjaxing
  xhr = pjax.xhr
  if xhr and xhr.readyState < 4
    xhr.onreadystatechange = $.noop
    xhr.abort()


  pjax.options = options
  pjax.xhr = $.ajax(options)

  # pjax event is deprecated
  $(document).trigger "pjax", [pjax.xhr, options]

  pjax.xhr

$.pjax = pjax

# Internal: Generate unique id for state object.
#
# Use a timestamp instead of a counter since ids should still be
# unique across page loads.
#
# Returns Number.
uniqueId = ->
  (new Date).getTime()

# Internal: Strips _pjax param from url
#
# url - String
#
# Returns String.
stripPjaxParam = (url) ->
  url
    .replace(/\?_pjax=[^&]+&?/, "?")
    .replace(/_pjax=[^&]+&?/, "")
    .replace(/[\?&]$/, "")

# Internal: Parse URL components and returns a Locationish object.
#
# url - String URL
#
# Returns HTMLAnchorElement that acts like Location.
parseURL = (url) ->
  a = document.createElement("a")
  a.href = url
  a

# Internal: Build options Object for arguments.
#
# For convenience the first parameter can be either the container or
# the options object.
#
# Examples
#
#   optionsFor("#container")
#   # => {container: "#container"}
#
#   optionsFor("#container", {push: true})
#   # => {container: "#container", push: true}
#
#   optionsFor({container: "#container", push: true})
#   # => {container: "#container", push: true}
#
# Returns options Object.
optionsFor = (container, options) ->
  # Both container and options
  if container and options
    options.container = container

  # First argument is options Object
  else if $.isPlainObject(container)
    options = container

  # Only container
  else
    options = 
      container: container

  # Find and validate container
  options.container = findContainerFor(options.container) if (options.container)

  options

# Internal: Find container element for a variety of inputs.
#
# Because we can't persist elements using the history API, we must be
# able to find a String selector that will consistently find the Element.
#
# container - A selector String, jQuery object, or DOM Element.
#
# Returns a jQuery object whose context is `document` and has a selector.
findContainerFor = (container) ->
  container = $(container)

  unless container.length 
    throw "no pjax container for #{container.selector}"
  else if container.selector isnt "" and container.context is document
    container
  else if container.attr("id") 
    $("##{container.attr("id")}")
  else
    throw "cant get selector for pjax container!"

# Internal: Filter and find all elements matching the selector.
#
# Where $.fn.find only matches descendants, findAll will test all the
# top level elements in the jQuery object as well.
#
# elems    - jQuery object of Elements
# selector - String selector to match
#
# Returns a jQuery object.
findAll = (elems, selector) ->
  results = $()

  elems.each ->
    results = results.add(@) if $(@).is(selector)
    results = results.add(selector, @)
    return
  
  results

# Internal: Extracts container and metadata from response.
#
# 1. Extracts X-PJAX-URL header if set
# 2. Extracts inline <title> tags
# 3. Builds response Element and extracts fragment if set
#
# data    - String response data
# xhr     - XHR response
# options - pjax options Object
#
# Returns an Object with url, title, and contents keys.
extractContainer = (data, xhr, options) ->
  obj = {}

  # Prefer X-PJAX-URL header if it was set, otherwise fallback to
  # using the original requested url.
  obj.url = stripPjaxParam(xhr.getResponseHeader("X-PJAX-URL") or options.url)

  # Attempt to parse response html into elements
  $data = $(data)

  # If response data is empty, return fast
  return obj if $data.length == 0
  
  # If there"s a <title> tag in the response, use it as
  # the page"s title.
  obj.title = findAll($data, "title").last().text()

  if options.fragment
    # If they specified a fragment, look for it in the response
    # and pull it out.
    $fragment = findAll($data, options.fragment).first()

    if $fragment.length
      obj.contents = $fragment.contents()

      # If there"s no title, look for data-title and title attributes
      # on the fragment
      obj.title = $fragment.attr("title") or $fragment.data("title") if (!obj.title)
      
  else obj.contents = $data if (!/<html/i.test(data)) 
  


  # Clean up any <title> tags
  if obj.contents
    # Remove any parent title elements
    obj.contents = obj.contents.not("title")

    # Then scrub any titles from their descendents
    obj.contents.find("title").remove()

  # Trim any whitespace off the title
  obj.title = $.trim(obj.title) if obj.title

  obj

# Public: Reload current page with pjax.
#
# Returns whatever $.pjax returns.
pjax.reload = (container, options) ->
  defaults = 
    url: window.location.href
    push: false
    replace: true
    scrollTo: false

  $.pjax $.extend(defaults, optionsFor(container, options))


pjax.defaults = 
  timeout: 650
  push: true
  replace: false
  type: "GET"
  dataType: "html"
  scrollTo: 0
  maxCacheLength: 20


# Internal: History DOM caching class.
class Cache 
  mapping: {}
  forwardStack: []
  backStack: []

  # Push previous state id and container contents into the history
  # cache. Should be called in conjunction with `pushState` to save the
  # previous container contents.
  #
  # id    - State ID Number
  # value - DOM Element to cache
  #
  # Returns nothing.
  push: (id, value) =>
    @mapping[id] = value
    @backStack.push id

    # Remove all entires in forward history stack after pushing
    # a new page.
    delete @mapping[@forwardStack.shift()] while @forwardStack.length
    

    # Trim back history stack to max cache length.
    delete @mapping[@backStack.shift()] while @backStack.length > pjax.defaults.maxCacheLength
  
    return
    
  # Retrieve cached DOM Element for state id.
  #
  # id - State ID Number
  #
  # Returns DOM Element(s) or undefined if cache miss.
  get: (id) =>
    return @mapping[id]

  # Shifts cache from forward history cache to back stack. Should be
  # called on `popstate` with the previous state id and container
  # contents.
  #
  # id    - State ID Number
  # value - DOM Element to cache
  #
  # Returns nothing.
  forward: (id, value) =>
    @mapping[id] = value
    @backStack.push id
  
    delete @mapping[id] if id = @forwardStack.pop()
    return
    
  # Shifts cache from back history cache to forward stack. Should be
  # called on `popstate` with the previous state id and container
  # contents.
  #
  # id    - State ID Number
  # value - DOM Element to cache
  #
  # Returns nothing.
  back: (id, value) =>
    @mapping[id] = value
    @forwardStack.push(id)

    delete @mapping[id] if id = @backStack.pop()     
    return 

containerCache = new Cache

# Export $.pjax.click
pjax.click = handleClick

# Used to detect initial (useless) popstate.
# If history.state exists, assume browser isn't going to fire initial popstate.
popped = "state" of window.history
initialURL = location.href

# popstate handler takes care of the back and forward buttons
#
# You probably shouldn't use pjax on pages with other pushState
# stuff yet.
$(window).bind "popstate", (event) ->
  # Ignore inital popstate that some browsers fire on page load
  initialPop = not popped and location.href is initialURL
  popped = true

  return if initialPop

  state = event.state

  if state and state.container
    container = $(state.container)
    if (container.length) 
      contents = containerCache.get state.id

      if pjax.state
        # Since state ids always increase, we can deduce the history
        # direction from the previous state.
        direction = if pjax.state.id < state.id then "forward" else "back"

        # Cache current container before replacement and inform the
        # cache which direction the history shifted.
        containerCache[direction](pjax.state.id, container.clone(true, true).contents())

      options =
        id: state.id
        url: state.url
        container: container
        push: false
        fragment: state.fragment
        timeout: state.timeout
        scrollTo: false

      if contents
        container.trigger "pjax:start", [null, options]

        container.html(contents)
        pjax.state = state

        container.trigger "pjax:end", [null, options]
      else
        $.pjax(options)
    

      # Force reflow/relayout before the browser tries to restore the
      # scroll position.
      container[0].offsetHeight
    else 
      window.location = location.href

# Add the state property to jQuery"s event object so we can use it in
# $(window).bind("popstate")
$.event.props.push("state") if $.inArray("state", $.event.props) < 0



# Is pjax supported by this browser?
$.support.pjax =
  # pushState isn't reliable on iOS until 5.
  window.history and 
  window.history.pushState and 
  window.history.replaceState and 
  not navigator.userAgent.match(/((iPod|iPhone|iPad).+\bOS\s+[1-4]|WebApps\/.+CFNetwork)/)

# Fall back to normalcy for older browsers.
unless $.support.pjax 
  $.pjax = (options) ->
    url = if $.isFunction(options.url) then options.url() else options.url
    method = (if options.type then options.type.toUpperCase() else "GET")

    form = $("<form>", 
      method: (if method == "GET" then "GET" else "POST")
      action: url
      style: "display:none"
    )
    if method isnt "GET" and method isnt "POST"
      form.append $("<input>", 
        type: "hidden"
        name: "_method"
        value: method.toLowerCase()
      )

    data = options.data
    if typeof data is "string"
      $.each data.split("&"), (index, value) ->
        pair = value.split("=")
        form.append $("<input>", 
          type: "hidden"
          name: pair[0]
          value: pair[1]
        )
    else if typeof data is "object"
      for key of data
        form.append $("<input>", 
          type: "hidden"
          name: key
          value: data[key]
        )  

    $(document.body).append form
    form.submit()
    return

  $.pjax.click = $.noop
  $.pjax.reload = window.location.reload
  $.fn.pjax = () -> 
    @ 