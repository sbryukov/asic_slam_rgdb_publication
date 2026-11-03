-- Pandoc Lua filter: LaTeX article -> GitHub Wiki Markdown.
-- Run AFTER --citeproc. Handles numbering, cross-references, numeric
-- citations, title block, table of contents and GitHub-incompatible markup.
--
-- Metadata it reads (pass with -M):
--   pdf_url     link to the PDF in the wiki repository
--   pdf_name    file name shown in the download link
--   build_info  one line under the link (commit, date)
--   asset_base  URL prefix for images (relative paths are fragile in wikis:
--               the Home page is served both as /wiki and /wiki/Home)

local stringify = pandoc.utils.stringify

local asset_base = nil
local labels = {}          -- id -> {kind=, num=, slug=}
local slug_count = {}
local cite_num, cite_order = {}, {}

local NAMES = {
  section = "Section", figure = "Figure", table = "Table",
  algorithm = "Algorithm", equation = "Equation",
}

-- GitHub heading anchor (same algorithm as github-slugger)
local function gh_slug(text)
  local s = pandoc.text.lower(text)
  s = s:gsub("[%p]", function(c) if c == "-" or c == "_" then return c end return "" end)
  for _, u in ipairs{"–", "—", "“", "”", "‘", "’", "…", "«", "»", "×"} do
    s = s:gsub(u, "")
  end
  s = s:gsub(" ", "-")
  local n = slug_count[s]
  slug_count[s] = (n or 0) + 1
  if n then s = s .. "-" .. n end
  return s
end

local function letter(n) return string.char(64 + n) end

local function caption_prefix(cap, text)
  local lead = pandoc.Strong(pandoc.Inlines(text .. "."))
  if #cap.long > 0 and cap.long[1].content then
    cap.long[1].content:insert(1, pandoc.Space())
    cap.long[1].content:insert(1, lead)
  else
    cap.long = pandoc.Blocks{ pandoc.Plain{ lead } }
  end
  return cap
end

-- Caption as a separate paragraph (GitHub has no figure/table captions).
local function caption_para(cap)
  local inl = pandoc.Inlines{}
  for _, b in ipairs(cap.long) do
    if b.content then inl:extend(b.content) end
  end
  return pandoc.Para{ pandoc.Emph(inl) }
end

---------------------------------------------------------------------------
-- Pass 1: number sections, figures, tables, equations; collect labels.
---------------------------------------------------------------------------
local function number_everything(blocks)
  local sec = {0, 0, 0, 0, 0, 0}
  local fig, tab, alg, eq = 0, 0, 0, 0
  local appendix = false
  local toc = {}
  local out = pandoc.Blocks{}

  local function number_eqs(el)
    return el:walk{
      Math = function(m)
        if m.mathtype ~= "DisplayMath" then return nil end
        local text = m.text
        local lbl = text:match("\\label%{([^}]+)%}")
        text = text:gsub("\\label%{[^}]*%}", "")
        if lbl then
          eq = eq + 1
          labels[lbl] = {kind = "equation", num = tostring(eq)}
          text = text .. " \\tag{" .. eq .. "}"
        end
        m.text = text
        return m
      end
    }
  end

  for _, b in ipairs(blocks) do
    if b.t == "Div" and b.classes:includes("wikiappendix") then
      appendix = true
      sec = {0, 0, 0, 0, 0, 0}
    elseif b.t == "Header" then
      if not b.classes:includes("unnumbered") and b.level <= 3 then
        sec[b.level] = sec[b.level] + 1
        for i = b.level + 1, 6 do sec[i] = 0 end
        local parts = {}
        for i = 1, b.level do
          parts[i] = (i == 1 and appendix) and letter(sec[1]) or tostring(sec[i])
        end
        local num = table.concat(parts, ".")
        b.content:insert(1, pandoc.Space())
        b.content:insert(1, pandoc.Str(num))
        local slug = gh_slug(stringify(b.content))
        if b.identifier ~= "" then
          labels[b.identifier] = {
            kind = appendix and b.level == 1 and "appendix" or "section",
            num = num, slug = slug}
        end
        if b.level <= 2 then
          toc[#toc + 1] = {level = b.level, text = stringify(b.content), slug = slug}
        end
      else
        local slug = gh_slug(stringify(b.content))
        if b.level == 1 then
          toc[#toc + 1] = {level = 1, text = stringify(b.content), slug = slug}
        end
      end
      b.level = b.level + 1        -- H1 is reserved for the paper title
      b.identifier = ""
      out:insert(b)
    elseif b.t == "Figure" then
      local is_alg = b.identifier:match("^alg:")
      local name, n
      if is_alg then alg = alg + 1; name, n = "Algorithm", alg
      else fig = fig + 1; name, n = "Figure", fig end
      if b.identifier ~= "" then
        labels[b.identifier] = {kind = name:lower(), num = tostring(n)}
      end
      local cap = caption_prefix(b.caption, name .. " " .. n)
      -- figure body: images centred in a paragraph, caption below
      local imgs = pandoc.Inlines{}
      b.content:walk{ Image = function(img)
        img.caption = pandoc.Inlines{}
        img.attributes = {}
        if asset_base and not img.src:match("^%a+://") then
          img.src = asset_base .. img.src
        end
        imgs:insert(img)
      end }
      out:insert(pandoc.Para(imgs))
      out:insert(caption_para(cap))
    elseif b.t == "Div" and #b.content >= 1 and b.content[1].t == "Table" then
      tab = tab + 1
      if b.identifier ~= "" then
        labels[b.identifier] = {kind = "table", num = tostring(tab)}
      end
      local t = b.content[1]
      local para = caption_para(caption_prefix(t.caption, "Table " .. tab))
      t.caption.long = pandoc.Blocks{}
      t.caption.short = nil
      out:insert(para)
      out:insert(number_eqs(t))
      for i = 2, #b.content do out:insert(b.content[i]) end
    else
      out:insert(number_eqs(b))
    end
  end
  return out, toc
end

---------------------------------------------------------------------------
-- Pass 2: resolve \ref / \cref / \eqref, citations, cosmetic clean-up.
---------------------------------------------------------------------------
local function ref_text(info, rtype)
  if rtype == "eqref" then return "(" .. info.num .. ")" end
  local word = info.kind == "appendix" and "Appendix" or NAMES[info.kind]
  if rtype == "ref+Label" or rtype == "ref+label" then
    if info.kind == "equation" then return "Eq. (" .. info.num .. ")" end
    return word .. " " .. info.num
  end
  return info.num
end

local resolve = {
  Link = function(l)
    local rtype = l.attributes["reference-type"]
    if not rtype then return nil end
    local key = l.attributes["reference"]
    local info = labels[key]
    if not info then
      io.stderr:write("wiki.lua: unresolved reference " .. key .. "\n")
      return pandoc.Str("??")
    end
    local txt = ref_text(info, rtype)
    if info.slug then return pandoc.Link(txt, "#" .. info.slug) end
    return pandoc.Str(txt)
  end,

  Cite = function(c)
    local nums = {}
    for _, ct in ipairs(c.citations) do
      local id = ct.id
      if not cite_num[id] then
        cite_order[#cite_order + 1] = id
        cite_num[id] = #cite_order
      end
      nums[#nums + 1] = cite_num[id]
    end
    table.sort(nums)
    local parts = {}
    for _, n in ipairs(nums) do parts[#parts + 1] = tostring(n) end
    return pandoc.Str("[" .. table.concat(parts, ", ") .. "]")
  end,

  -- GitHub strips inline styles and unknown classes: keep the text only.
  Span = function(s) return s.content end,
  SmallCaps = function(s) return s.content end,
  Div = function(d)
    if d.identifier == "refs" or d.classes:includes("csl-entry") then return nil end
    return d.content
  end,
  -- **a **b** c** is not valid Markdown (e.g. \NUM inside \TODO)
  Strong = function(s)
    s.content = s.content:walk{ Strong = function(i) return i.content end }
    return s
  end,
}

---------------------------------------------------------------------------
-- References: numeric order of first citation, "[n] entry".
---------------------------------------------------------------------------
local function build_references(blocks)
  local entries, out = {}, pandoc.Blocks{}
  local refs_found = false
  for _, b in ipairs(blocks) do
    if b.t == "Div" and b.identifier == "refs" then
      refs_found = true
      for _, e in ipairs(b.content) do
        if e.t == "Div" then
          entries[e.identifier:gsub("^ref%-", "")] = e.content
        end
      end
    else
      out:insert(b)
    end
  end
  if not refs_found then return out, nil end
  -- uncited (\nocite) entries go last
  for id, _ in pairs(entries) do
    if not cite_num[id] then
      cite_order[#cite_order + 1] = id; cite_num[id] = #cite_order
    end
  end
  local list = pandoc.Blocks{}
  list:insert(pandoc.Header(2, "References"))
  for n, id in ipairs(cite_order) do
    local content = entries[id]
    if content then
      local inl = pandoc.Inlines{ pandoc.Str("[" .. n .. "]"), pandoc.Space() }
      for _, b in ipairs(content) do
        if b.content then inl:extend(b.content) end
      end
      list:insert(pandoc.Para(inl:walk(resolve)))
    end
  end
  return out, list
end

---------------------------------------------------------------------------
function Pandoc(doc)
  local meta = doc.meta
  asset_base = meta.asset_base and stringify(meta.asset_base) or nil
  -- citeproc puts the bibliography at the end of the document; the appendix
  -- (after \bibliography in LaTeX) must follow it, as in the PDF.
  local body, toc = number_everything(doc.blocks)
  body = body:walk(resolve)
  local main, refs = build_references(body)

  local head = pandoc.Blocks{}
  local title = meta.title and stringify(meta.title):gsub("^%s+", ""):gsub("%s+$", "")
  head:insert(pandoc.Header(1, title or "Paper"))

  -- authors: "Name, affiliation; Name, affiliation"
  if meta.author then
    local authors = pandoc.Inlines{}
    local list = pandoc.utils.type(meta.author) == "List" and meta.author or {meta.author}
    for i, a in ipairs(list) do
      if i > 1 then authors:extend{pandoc.Str(";"), pandoc.Space()} end
      local inl = pandoc.Inlines(a):walk({
        LineBreak = function() return pandoc.Inlines{pandoc.Str(","), pandoc.Space()} end,
        Span = function(s) return s.content end,
      })
      authors:extend(inl)
    end
    head:insert(pandoc.Para(authors))
  end

  if meta.pdf_url then
    head:insert(pandoc.BlockQuote{
      pandoc.Para{
        pandoc.Str("📄"), pandoc.Space(),
        pandoc.Strong{ pandoc.Link(
          pandoc.Inlines("Download PDF (" .. stringify(meta.pdf_name or "paper.pdf") .. ")"),
          stringify(meta.pdf_url)) },
      },
      pandoc.Para{ pandoc.Emph(pandoc.Inlines(stringify(meta.build_info or ""))) },
    })
  end

  if meta.abstract then
    head:insert(pandoc.Header(2, "Abstract"))
    head:extend(pandoc.Blocks(meta.abstract):walk(resolve))
  end

  -- table of contents
  if #toc > 0 then
    head:insert(pandoc.Header(2, "Contents"))
    local items, sub = {}, nil
    for _, e in ipairs(toc) do
      local link = pandoc.Plain{ pandoc.Link(e.text, "#" .. e.slug) }
      if e.level == 1 then
        items[#items + 1] = {link}
      else
        local last = items[#items]
        if last then
          if #last == 1 then last[2] = pandoc.BulletList{} end
          last[2].content:insert({ link })
        end
      end
    end
    local refs_slug = refs and gh_slug("References")
    if refs_slug then
      items[#items + 1] = { pandoc.Plain{ pandoc.Link("References", "#" .. refs_slug) } }
    end
    head:insert(pandoc.BulletList(items))
    head:insert(pandoc.HorizontalRule())
  end

  -- place references before the appendix (as in the PDF)
  local final = pandoc.Blocks{}
  final:extend(head)
  local inserted = false
  for _, b in ipairs(main) do
    if refs and not inserted and b.t == "Header" and b.level == 2
       and stringify(b.content):match("^[A-Z] ") then
      final:extend(refs); inserted = true
    end
    final:insert(b)
  end
  if refs and not inserted then final:extend(refs) end

  return pandoc.Pandoc(final, pandoc.Meta{})
end
