
-- Use LuaRocks if available
pcall(require, "luarocks.require");

local server = require "net.server";
local events = require "util.events";

module("verse", package.seeall);
local verse = _M;

local stream = {};
stream.__index = stream;
stream_mt = stream;

verse.plugins = {};

function verse.new(logger, base)
	local t = setmetatable(base or {}, stream);
	t.id = tostring(t):match("%x*$");
	t:set_logger(logger, true);
	t.events = events.new();
	return t;
end

verse.add_task = require "util.timer".add_task;

function verse.loop()
	return server.loop();
end

function verse.quit()
	return server.setquitting(true);
end

verse.logger = logger.init;

function verse.set_logger(logger)
	server.setlogger(logger);
end

function stream:connect(connect_host, connect_port)
	connect_host = connect_host or "localhost";
	connect_port = tonumber(connect_port) or 5222;
	
	-- Create and initiate connection
	local conn = socket.tcp()
	conn:settimeout(0);
	local success, err = conn:connect(connect_host, connect_port);
	
	if not success and err ~= "timeout" then
		self:warn("connect() to %s:%d failed: %s", connect_host, connect_port, err);
		return false, err;
	end

	--local conn, err = server.addclient(self.connect_host or self.host, tonumber(self.connect_port) or 5222, new_listener(self), "*a");
	local conn = server.wrapclient(conn, connect_host, connect_port, new_listener(self), "*a"); --, hosts[from_host].ssl_ctx, false );
	if not conn then
		return nil, err;
	end
	
	self.conn = conn;
	local w, t = conn.write, tostring;
	self.send = function (_, data) return w(conn, t(data)); end
end

-- Logging functions
function stream:debug(...)
	if self.logger and self.log.debug then
		return self.logger("debug", ...);
	end
end

function stream:warn(...)
	if self.logger and self.log.warn then
		return self.logger("warn", ...);
	end
end

function stream:error(...)
	if self.logger and self.log.error then
		return self.logger("error", ...);
	end
end

function stream:set_logger(logger, levels)
	local old_logger = self.logger;
	if logger then
		self.logger = logger;
	end
	if levels then
		if levels == true then
			levels = { "debug", "info", "warn", "error" };
		end
		self.log = {};
		for _, level in ipairs(levels) do
			self.log[level] = true;
		end
	end
	return old_logger;
end

-- Event handling
function stream:event(name, ...)
	self:debug("Firing event: "..tostring(name));
	return self.events.fire_event(name, ...);
end

function stream:hook(name, ...)
	return self.events.add_handler(name, ...);
end

function stream:unhook(name, handler)
	return self.events.remove_handler(name, handler);
end

function stream:add_plugin(name)
	if require("verse.plugins."..name) then
		local ok, err = verse.plugins[name](self);
		if ok then
			self:debug("Loaded %s plugin", name);
		else
			self:warn("Failed to load %s plugin: %s", name, err);
		end
	end
	return self;
end

-- Listener factory
function new_listener(stream)
	local conn_listener = {};
	
	function conn_listener.onconnect(conn)
		stream.connected = true;
		stream.send = function (stream, data) stream:debug("Sending data: "..tostring(data)); return conn:write(tostring(data)); end;
		stream:event("connected");
	end
	
	function conn_listener.onincoming(conn, data)
		stream:event("incoming-raw", data);
	end
	
	function conn_listener.ondisconnect(conn, err)
		stream.connected = false;
		stream:event("disconnected", { reason = err });
	end

	function conn_listener.ondrain(conn)
		stream:event("drained");
	end
	
	return conn_listener;
end


local log = require "util.logger".init("verse");

return verse;
