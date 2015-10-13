-- vim:sw=4:sts=4

-- Sections plugin.

local lfs = require 'lfs'
local luapress = require 'luapress'
local util = require('luapress.util')
local markdown = require('luapress.lib.markdown')
local template = require('luapress.template')

---
-- Make sure all the directories leading to the given file exist.
-- The file itself might not exist yet.
--
-- @param path  Path and filename.
--
local function _mkdir(path)
    local s = ""
    for w in string.gmatch(path, "[^/]+/") do
	s = s .. w
	lfs.mkdir(s)
    end
end


---
-- Copy a file.  All the directories leading to the destination file are
-- automatically created.
--
-- @param from   Source file
-- @param to  Destination file
--
local function _file_copy(from, to)
    local f_from, f_to, buf

    f_from = lfs.attributes(from)
    f_to = lfs.attributes(to)

    -- Skip unchanged files.
    if f_from and f_to and f_from.size == f_to.size and f_from.modification
	<= f_to.modification then
	return
    end

    if config.print then print("Copying " .. from) end

    f_from = io.open(from, "rb")
    assert(f_from)
    _mkdir(to)

    -- try to hardlink.
    local rc = lfs.link(from, to)
    if rc == 0 then
	return
    end

    f_to = io.open(to, "wb")
    assert(f_to)

    while true do
	buf = f_from:read("*a", 2048)
	if not buf or #buf == 0 then break end
	f_to:write(buf)
    end

    f_from:close()
    f_to:close()
end

-- Builds link list based on the currently active page
local function _page_links(pages, active, dir)
    local output = ''

    for k, page in pairs(pages) do
        if not page.hidden then
	  if page.link == active then
	    output = output .. '<li class="active"><a href="' .. config.url .. '/sections/' .. dir .. '/' .. active .. '">' .. page.title .. '</a></li>\n'
	  else
	    output = output .. '<li><a href="' .. config.url .. '/sections/' .. dir  .. '/' .. page.link .. '">' .. page.title .. '</a></li>\n'
	  end
        end
    end

    return output
end

---
-- Loads all .lhtml files from a template directory
--
local function _load_templates( path )
    local templates = {}
    local directory = path

    for file in lfs.dir(directory) do
        if file:sub(-5) == 'lhtml' then
            local tmpl_name = file:sub(9, -7)	    
-- 	    print( tmpl_name )
            file = directory .. '/' .. file
            local f, err = io.open(file, 'r')
            if not f then error(err) end
            local s, err = f:read('*a')
            if not s then error(err) end
            f:close()

            templates[tmpl_name] = s
        end
    end

    return templates
end

---
-- Load all markdown files in a directory and preprocess them
-- into HTML.
--
-- @param directory  Subdirectory of config.root (pages or posts)
-- @param template  'page' or 'post'
-- @return  Table of items
--
local function _load_markdowns(directory, out_directory, template)
    local items = {}
--     local out_directory = config[directory .. '_dir']

    for file in lfs.dir( directory ) do
        if file:sub(-3) == '.md' then
            local fname = file:sub(0, -4)
	    local file2 = directory .. "/" .. file
--             local file2 = config.root .. "/" .. directory .. '/' .. file
            local attributes = lfs.attributes(file2)

            -- Work out link
            local link = fname:gsub(' ', '_'):gsub('[^_aA-zZ0-9]', '')
            link = link .. '.html'

            -- Get basic attributes
            local item = {
                source = directory .. '/' .. file, -- for error messages
                link = link, -- basename of output file
                name = fname, -- same as title, but is not overwritten
                title = fname, -- displayed page name
                directory = directory, -- relative to config.root
                content = '',
                time = attributes.modification, -- to check build requirement
                modification = attributes.modification, -- stored separately as time can be overwritten w/$time=
                template = template, -- what template will be used (type of item)
            }

            -- Now read the file
            local f = assert(io.open(file2, 'r'))
            local s = assert(f:read('*a'))

            -- Set $=key's
            s = s:gsub('%$=url', config.url)

            -- Get $key=value's (and remove from string)
            for k, v in s:gmatch('%$([%w]+)=(.-)\n') do
                item[k] = v
            end
            s = s:gsub('%$[%w]+=.-\n', '')

            -- Excerpt
            local start, _ = s:find('--MORE--', 1, true)
            if start then
                -- Extract the excerpt
                item.excerpt = markdown(s:sub(0, start - 1))
                -- Replace the --MORE--
                local sep = config.more_separator or ''
                s = s:gsub('%-%-MORE%-%-', '<a id="more">' .. sep .. '</a>')
            end

            item.content = markdown(s)
	    
-- 	    print ( item.content )

            -- Date set?
            if item.date then
                local _, _, d, m, y = item.date:find('(%d+)%/(%d+)%/(%d+)')
                item.time = os.time({day = d, month = m, year = y})
            end

            -- Insert to items
        items[#items + 1] = item
            if config.print then print('\t' .. item.title) end
        end
    end

    return items
end

local function process(inpage, arg)

--     -- determine the image directory, verify that it exists
    local dir = arg.dir or inpage.name
    local dir2 = 'sections/' .. dir
    
    local s = lfs.attributes(dir2, "mode")
    if s ~= 'directory' then
	error("Section: not a directory: " .. dir2)
	return
    end

    local outdir = config.build_dir .. "/" .. dir2
    -- create output paths
    lfs.mkdir(config.build_dir .. "/sections")
    lfs.mkdir(outdir)

    local images = {}
    for f in lfs.dir(dir2) do
	if f ~= '.' and f ~= '..' and ( f:sub(-4) == '.jpg' or f:sub(-4) == '.png') then
	    -- print("Image", dir2 .. '/' .. f)
	    -- XXX verify that it is a JPG file (maybe others are OK)
	    local img = {
		-- img0001.jpg
		imgname = f,
		-- subdir
		subdir = dir,
		-- gallery/subdir/img0001.jpg
		source = dir2 .. '/' .. f,
		-- build/gallery/subdir/images/img0001.jpg
		dest = config.build_dir .. '/' .. dir2 .. '/' .. f,
	    }
	    images[#images + 1] = img
	end
    end
    -- copy source images (if changed or missing)
    for i, img in ipairs(images) do
	_file_copy(img.source, img.dest)
    end
    
    local templates = _load_templates( arg.plugin_path )
    
    local pages = _load_markdowns( dir2, outdir, 'page' )
    -- the original function will be recursive!!!
--     local pages = util.load_markdowns('pages', 'page', 'section_page')
    table.sort(pages, function(a, b)
        return (tonumber(a.order) or 0) < (tonumber(b.order) or 0)
    end)
  
    local pagelinklist = ''
    for _, page in ipairs(pages) do
        local dest_file = util.ensure_destination(page)

        -- We're a page, so change up page_links
        template:set('page_links', _page_links(pages, page.link, dir))
        template:set('page', page)
	template:set('section_name', inpage.title )

	pagelinklist = pagelinklist .. '<li><a href="' .. config.url .. '/sections/' .. dir  .. '/' .. page.link .. '">' .. page.title .. '</a></li>\n'

        -- Output the file
        util.write_html(dest_file, page, templates)
    end
    
    -- copy style.css
    _file_copy(arg.plugin_path .. '/section_style.css', config.build_dir .. '/inc/template/section_style.css')

    -- protect from markdown
    return "<ul>" .. pagelinklist .. "</ul>"
end

return process