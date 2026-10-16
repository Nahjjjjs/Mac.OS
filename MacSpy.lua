-- Remote Spy | macOS style | Delta / mobile
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local TS = game:GetService("TweenService")
local lp = Players.LocalPlayer

local C = {
	win = Color3.fromRGB(30, 30, 32), side = Color3.fromRGB(38, 38, 42),
	bar = Color3.fromRGB(46, 46, 50), line = Color3.fromRGB(64, 64, 70),
	text = Color3.fromRGB(235, 235, 240), dim = Color3.fromRGB(142, 142, 150),
	accent = Color3.fromRGB(10, 132, 255), red = Color3.fromRGB(255, 95, 87),
	yellow = Color3.fromRGB(254, 188, 46), green = Color3.fromRGB(40, 200, 64),
	orange = Color3.fromRGB(255, 159, 10), purple = Color3.fromRGB(191, 90, 242),
}

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do o[k] = v end
	o.Parent = parent
	return o
end
local function round(o, r) new("UICorner", {CornerRadius = UDim.new(0, r)}, o) end
local function label(p, parent)
	p.BackgroundTransparency = 1
	p.Font = p.Font or Enum.Font.Gotham
	p.TextColor3 = p.TextColor3 or C.text
	p.TextSize = p.TextSize or 13
	return new("TextLabel", p, parent)
end

---------------------------------------------------------------- serializer
local function esc(s)
	return (s:gsub('[%c\\"]', function(c) return string.format("\\%03d", c:byte()) end))
end

local function path(i)
	if i == lp then return 'game:GetService("Players").LocalPlayer' end
	local chain, cur = {}, i
	while cur and cur ~= game do table.insert(chain, 1, cur) cur = cur.Parent end
	if cur ~= game then return "nil --[[ " .. tostring(i) .. " (not in game) ]]" end
	local out = "game"
	for idx, o in ipairs(chain) do
		local isSvc = false
		if idx == 1 then
			local ok, svc = pcall(game.FindService, game, o.ClassName)
			isSvc = ok and svc == o
		end
		if isSvc then out = 'game:GetService("' .. o.ClassName .. '")'
		elseif o.Name:match("^[%a_][%w_]*$") then out = out .. "." .. o.Name
		else out = out .. '["' .. esc(o.Name) .. '"]' end
	end
	return out
end

local function ser(v, d, seen)
	d = d or 0
	seen = seen or {}
	local t = typeof(v)
	if t == "string" then return '"' .. esc(v) .. '"'
	elseif t == "number" then
		if v ~= v then return "0/0" elseif v == math.huge then return "math.huge" elseif v == -math.huge then return "-math.huge" end
		return tostring(v)
	elseif t == "boolean" or t == "nil" then return tostring(v)
	elseif t == "Instance" then return path(v)
	elseif t == "Vector3" then return string.format("Vector3.new(%s, %s, %s)", v.X, v.Y, v.Z)
	elseif t == "Vector2" then return string.format("Vector2.new(%s, %s)", v.X, v.Y)
	elseif t == "CFrame" then return "CFrame.new(" .. table.concat({v:GetComponents()}, ", ") .. ")"
	elseif t == "Color3" then return string.format("Color3.new(%s, %s, %s)", v.R, v.G, v.B)
	elseif t == "UDim2" then return string.format("UDim2.new(%s, %s, %s, %s)", v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset)
	elseif t == "UDim" then return string.format("UDim.new(%s, %s)", v.Scale, v.Offset)
	elseif t == "BrickColor" then return 'BrickColor.new("' .. v.Name .. '")'
	elseif t == "EnumItem" then return tostring(v)
	elseif t == "table" then
		if seen[v] then return "{} --[[cyclic]]" end
		if d > 6 then return "{} --[[depth]]" end
		local n = 0
		for _ in pairs(v) do n += 1 end
		if n == 0 then return "{}" end
		seen[v] = true
		local pad, out = string.rep("\t", d + 1), {}
		if #v == n then
			for i = 1, n do out[#out + 1] = pad .. ser(v[i], d + 1, seen) end
		else
			for k, val in pairs(v) do
				local ks = (type(k) == "string" and k:match("^[%a_][%w_]*$")) and k or ("[" .. ser(k, d + 1, seen) .. "]")
				out[#out + 1] = pad .. ks .. " = " .. ser(val, d + 1, seen)
			end
		end
		seen[v] = nil
		return "{\n" .. table.concat(out, ",\n") .. ",\n" .. string.rep("\t", d) .. "}"
	end
	return "nil --[[ " .. t .. ": " .. tostring(v) .. " ]]"
end
local function safeSer(v, d)
	local ok, s = pcall(ser, v, d)
	return ok and s or "nil --[[ serialize error ]]"
end

local function genCode(remote, method, args, rets)
	local L = {"-- " .. remote.ClassName .. ": " .. remote.Name, "local args = {"}
	for i = 1, args.n do L[#L + 1] = "\t[" .. i .. "] = " .. safeSer(args[i], 1) .. "," end
	L[#L + 1] = "}"
	L[#L + 1] = path(remote) .. ":" .. method .. "(unpack(args, 1, " .. args.n .. "))"
	if rets and rets.n > 0 then
		L[#L + 1] = ""
		for i = 1, rets.n do
			local s = safeSer(rets[i], 0):gsub("%s+", " ")
			if #s > 240 then s = s:sub(1, 240) .. "..." end
			L[#L + 1] = "-- returned[" .. i .. "]: " .. s
		end
	end
	return table.concat(L, "\n")
end

---------------------------------------------------------------- gui
local gui = new("ScreenGui", {Name = "MacSpy", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling})
if not pcall(function() gui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end) then
	gui.Parent = lp:WaitForChild("PlayerGui")
end

local vp = workspace.CurrentCamera.ViewportSize
local normal = UDim2.fromOffset(math.min(600, vp.X - 24), math.min(340, vp.Y - 70))
local win = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -20), Size = normal,
	BackgroundColor3 = C.win, BackgroundTransparency = 0.04, BorderSizePixel = 0, ClipsDescendants = true,
}, gui)
round(win, 10)
new("UIStroke", {Color = C.line, Thickness = 1}, win)

local bar = new("Frame", {Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = C.bar, BorderSizePixel = 0}, win)
label({Size = UDim2.new(1, 0, 1, 0), Text = "Remote Spy", Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = C.dim}, bar)

local function light(x, col)
	local b = new("TextButton", {Position = UDim2.new(0, x, 0.5, -7), Size = UDim2.fromOffset(14, 14), BackgroundColor3 = col, Text = "", AutoButtonColor = false}, bar)
	round(b, 7)
	return b
end
local closeB, minB, maxB = light(12, C.red), light(34, C.yellow), light(56, C.green)

-- toolbar
local tool = new("Frame", {Position = UDim2.new(0, 0, 0, 34), Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1}, win)
local function pill(x, w)
	local b = new("TextButton", {
		Position = UDim2.new(0, x, 0.5, -12), Size = UDim2.fromOffset(w, 24), BackgroundColor3 = C.bar,
		Text = "", TextColor3 = C.text, Font = Enum.Font.GothamMedium, TextSize = 12,
	}, tool)
	round(b, 6)
	new("UIStroke", {Color = C.line}, b)
	return b
end
local pauseB, clearB, copyB, runB, blockB, ignoreB = pill(10, 58), pill(74, 52), pill(132, 52), pill(190, 46), pill(242, 62), pill(310, 58)
local search = new("TextBox", {
	AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(120, 24),
	BackgroundColor3 = C.bar, Text = "", PlaceholderText = "Search", PlaceholderColor3 = C.dim,
	TextColor3 = C.text, Font = Enum.Font.Gotham, TextSize = 12, ClearTextOnFocus = false,
}, tool)
round(search, 12)

-- body
local body = new("Frame", {Position = UDim2.new(0, 0, 0, 68), Size = UDim2.new(1, 0, 1, -90), BackgroundTransparency = 1}, win)
local side = new("Frame", {Size = UDim2.new(0, 150, 1, 0), BackgroundColor3 = C.side, BorderSizePixel = 0}, body)
new("Frame", {AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0, 1, 1, 0), BackgroundColor3 = C.line, BorderSizePixel = 0}, side)
label({Position = UDim2.new(0, 12, 0, 6), Size = UDim2.new(1, -12, 0, 16), Text = "REMOTES", Font = Enum.Font.GothamBold, TextSize = 10, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Left}, side)

local function scroller(parent, pos, size)
	local s = new("ScrollingFrame", {
		Position = pos, Size = size, BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, parent)
	new("UIListLayout", {Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder}, s)
	new("UIPadding", {PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), PaddingTop = UDim.new(0, 2)}, s)
	return s
end
local sideList = scroller(side, UDim2.new(0, 0, 0, 24), UDim2.new(1, -1, 1, -24))

local main = new("Frame", {Position = UDim2.new(0, 150, 0, 0), Size = UDim2.new(1, -150, 1, 0), BackgroundTransparency = 1}, body)
local callList = scroller(main, UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 0.38, 0))
new("Frame", {Position = UDim2.new(0, 0, 0.38, 0), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = C.line, BorderSizePixel = 0}, main)
local code = new("TextBox", {
	Position = UDim2.new(0, 0, 0.38, 1), Size = UDim2.new(1, 0, 0.62, -1), BackgroundColor3 = Color3.fromRGB(22, 22, 24),
	BorderSizePixel = 0, Text = "", PlaceholderText = "  select a remote", PlaceholderColor3 = C.dim, TextColor3 = Color3.fromRGB(200, 230, 190),
	Font = Enum.Font.Code, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
	MultiLine = true, TextEditable = false, ClearTextOnFocus = false, TextWrapped = true,
}, main)
new("UIPadding", {PaddingLeft = UDim.new(0, 8), PaddingTop = UDim.new(0, 6), PaddingRight = UDim.new(0, 8)}, code)

-- status bar
local status = new("Frame", {AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 22), BackgroundColor3 = C.bar, BorderSizePixel = 0}, win)
local statL = label({Position = UDim2.new(0, 10, 0, 0), Size = UDim2.new(0.5, 0, 1, 0), TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left}, status)
local statR = label({AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 0), Size = UDim2.new(0.5, 0, 1, 0), TextSize = 11, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Right}, status)

-- dock
local dock = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.fromOffset(64, 52),
	BackgroundColor3 = Color3.fromRGB(60, 60, 66), BackgroundTransparency = 0.25,
}, gui)
round(dock, 14)
new("UIStroke", {Color = C.line}, dock)
local icon = new("TextButton", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 5), Size = UDim2.fromOffset(38, 38),
	BackgroundColor3 = C.accent, Text = "RS", TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold, TextSize = 15,
}, dock)
round(icon, 10)
new("UIGradient", {Color = ColorSequence.new(C.accent, C.purple), Rotation = 45}, icon)
local dot = new("Frame", {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -1), Size = UDim2.fromOffset(4, 4), BackgroundColor3 = C.text}, dock)
round(dot, 2)

---------------------------------------------------------------- state
local entries, nEntries, totalCalls = {}, 0, 0
local blocked, ignored = {}, {}
local sel, selCall
local paused, active, hooked = false, true, false
local filter = ""
local selectCall, selectRemote

local function updateStatus()
	if not hooked then statL.Text = "● Hook failed (no hookmetamethod)" statL.TextColor3 = C.red
	elseif paused then statL.Text = "● Paused" statL.TextColor3 = C.yellow
	else statL.Text = "● Recording" statL.TextColor3 = C.green end
	statR.Text = nEntries .. " remotes  ·  " .. totalCalls .. " calls"
end

local function syncButtons()
	pauseB.Text = paused and "Resume" or "Pause"
	clearB.Text, copyB.Text, runB.Text = "Clear", "Copy", "Run"
	blockB.Text = (sel and blocked[sel.remote]) and "Unblock" or "Block"
	ignoreB.Text = (sel and ignored[sel.remote]) and "Watch" or "Ignore"
	updateStatus()
end
local function flash(b, t) b.Text = t task.delay(0.9, syncButtons) end

local function refreshEntry(e)
	e.name.TextColor3 = blocked[e.remote] and C.red or (ignored[e.remote] and C.dim or C.text)
end

local function getEntry(remote)
	local e = entries[remote]
	if e then return e end
	nEntries += 1
	e = {remote = remote, calls = {}, count = 0}
	entries[remote] = e
	local col = remote.ClassName == "RemoteFunction" and C.orange or (remote.ClassName == "UnreliableRemoteEvent" and C.purple or C.accent)
	local b = new("TextButton", {Size = UDim2.new(1, 0, 0, 26), BackgroundColor3 = C.accent, BackgroundTransparency = 1, Text = "", AutoButtonColor = false, LayoutOrder = nEntries}, sideList)
	round(b, 6)
	local d = new("Frame", {Position = UDim2.new(0, 8, 0.5, -4), Size = UDim2.fromOffset(8, 8), BackgroundColor3 = col}, b)
	round(d, 4)
	e.name = label({Position = UDim2.new(0, 22, 0, 0), Size = UDim2.new(1, -52, 1, 0), Text = remote.Name, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd}, b)
	e.badge = label({AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 0), Size = UDim2.new(0, 30, 1, 0), Text = "0", TextSize = 11, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Right}, b)
	e.btn = b
	b.MouseButton1Click:Connect(function() selectRemote(e) end)
	refreshEntry(e)
	b.Visible = filter == "" or remote.Name:lower():find(filter, 1, true) ~= nil
	return e
end

local function makeCallBtn(e, c)
	local b = new("TextButton", {Size = UDim2.new(1, 0, 0, 22), BackgroundColor3 = C.accent, BackgroundTransparency = 1, Text = "", AutoButtonColor = false, LayoutOrder = -c.id}, callList)
	round(b, 5)
	label({Position = UDim2.new(0, 8, 0, 0), Size = UDim2.new(1, -10, 1, 0), TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
		Text = string.format("#%d   %s   %d arg%s   %s", c.id, c.method, c.n, c.n == 1 and "" or "s", c.time)}, b)
	c.btn = b
	b.MouseButton1Click:Connect(function() selectCall(e, c) end)
end

selectCall = function(e, c)
	if selCall and selCall.btn and selCall.btn.Parent then selCall.btn.BackgroundTransparency = 1 end
	selCall = c
	if c.btn then c.btn.BackgroundTransparency = 0.25 end
	code.Text = c.code
end

selectRemote = function(e)
	if sel and sel.btn and sel.btn.Parent then sel.btn.BackgroundTransparency = 1 end
	sel, selCall = e, nil
	e.btn.BackgroundTransparency = 0.2
	for _, ch in ipairs(callList:GetChildren()) do if ch:IsA("TextButton") then ch:Destroy() end end
	for _, c in ipairs(e.calls) do makeCallBtn(e, c) end
	local last = e.calls[#e.calls]
	if last then selectCall(e, last) else code.Text = "" end
	syncButtons()
end

local function logCall(remote, method, args, rets)
	local ok = pcall(function()
		local e = getEntry(remote)
		e.count += 1
		totalCalls += 1
		local c = {id = e.count, method = method == "InvokeServer" and "Invoke" or "Fire", n = args.n, args = args, time = os.date("%H:%M:%S")}
		c.code = genCode(remote, method, args, rets)
		table.insert(e.calls, c)
		if #e.calls > 150 then
			local old = table.remove(e.calls, 1)
			if old.btn then old.btn:Destroy() end
		end
		e.badge.Text = tostring(e.count)
		if not sel then selectRemote(e)
		elseif sel == e then
			local follow = selCall == nil or selCall.id == e.count - 1
			makeCallBtn(e, c)
			if follow then selectCall(e, c) end
		end
		updateStatus()
	end)
end

---------------------------------------------------------------- buttons
pauseB.MouseButton1Click:Connect(function() paused = not paused syncButtons() end)
clearB.MouseButton1Click:Connect(function()
	for _, e in pairs(entries) do e.btn:Destroy() end
	for _, ch in ipairs(callList:GetChildren()) do if ch:IsA("TextButton") then ch:Destroy() end end
	entries, nEntries, totalCalls, sel, selCall = {}, 0, 0, nil, nil
	code.Text = ""
	syncButtons()
end)
copyB.MouseButton1Click:Connect(function()
	local cp = setclipboard or toclipboard
	if not (cp and selCall) then return flash(copyB, cp and "Empty" or "No clip") end
	cp(selCall.code)
	flash(copyB, "Copied")
end)
runB.MouseButton1Click:Connect(function()
	if not (sel and selCall) then return end
	local r, a = sel.remote, selCall.args
	task.spawn(function()
		pcall(function()
			if r.ClassName == "RemoteFunction" then r:InvokeServer(table.unpack(a, 1, a.n))
			else r:FireServer(table.unpack(a, 1, a.n)) end
		end)
	end)
	flash(runB, "Sent")
end)
blockB.MouseButton1Click:Connect(function()
	if not sel then return end
	blocked[sel.remote] = not blocked[sel.remote] or nil
	refreshEntry(sel) syncButtons()
end)
ignoreB.MouseButton1Click:Connect(function()
	if not sel then return end
	ignored[sel.remote] = not ignored[sel.remote] or nil
	refreshEntry(sel) syncButtons()
end)
search:GetPropertyChangedSignal("Text"):Connect(function()
	filter = search.Text:lower()
	for r, e in pairs(entries) do e.btn.Visible = filter == "" or r.Name:lower():find(filter, 1, true) ~= nil end
end)

-- traffic lights + dock
closeB.MouseButton1Click:Connect(function() active = false gui:Destroy() end)
minB.MouseButton1Click:Connect(function() win.Visible = false dot.Visible = false end)
icon.MouseButton1Click:Connect(function() win.Visible = not win.Visible dot.Visible = win.Visible end)
local maxed = false
maxB.MouseButton1Click:Connect(function()
	maxed = not maxed
	local v = workspace.CurrentCamera.ViewportSize
	local target = maxed and UDim2.fromOffset(v.X - 24, v.Y - 80) or normal
	TS:Create(win, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {Size = target, Position = UDim2.new(0.5, 0, 0.5, maxed and -26 or -20)}):Play()
end)

-- drag by title bar
local dragging, dragStart, startPos
bar.InputBegan:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
		dragging, dragStart, startPos = true, i.Position, win.Position
		i.Changed:Connect(function() if i.UserInputState == Enum.UserInputState.End then dragging = false end end)
	end
end)
UIS.InputChanged:Connect(function(i)
	if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
		local d = i.Position - dragStart
		win.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
	end
end)

---------------------------------------------------------------- hook
local oldNC
hooked = pcall(function()
	oldNC = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
		local method = getnamecallmethod()
		if active and (method == "FireServer" or method == "InvokeServer") and not checkcaller() and typeof(self) == "Instance" then
			local cn = self.ClassName
			if cn == "RemoteEvent" or cn == "RemoteFunction" or cn == "UnreliableRemoteEvent" then
				if blocked[self] then return end
				if not paused and not ignored[self] then
					local args = table.pack(...)
					if method == "InvokeServer" then
						if setnamecallmethod then setnamecallmethod(method) end
						local rets = table.pack(oldNC(self, ...))
						task.defer(logCall, self, method, args, rets)
						return table.unpack(rets, 1, rets.n)
					end
					task.defer(logCall, self, method, args)
				end
			end
		end
		if setnamecallmethod then setnamecallmethod(method) end
		return oldNC(self, ...)
	end))
end)

syncButtons()
