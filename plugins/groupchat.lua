local events = require "events";
local st = require "util.stanza";

local room_mt = {};
room_mt.__index = room_mt;

local xmlns_delay = "urn:xmpp:delay";
local xmlns_muc = "http://jabber.org/protocol/muc";

function verse.plugins.groupchat(stream)
	stream:add_plugin("presence")
	stream.rooms = {};
	
	stream:hook("stanza", function (stanza)
		local room_jid = jid.bare(stanza.attr.from);
		local room = stream.rooms[room_jid]
		if room then
			local nick = select(3, jid.split(stanza.attr.from));
			local body = stanza:get_child("body");
			local delay = stanza:get_child("delay", xmlns_delay);
			local event = {
				room_jid = room_jid;
				room = room;
				sender = room.occupants[nick];
				nick = nick;
				body = (body and body:get_text()) or nil;
				stanza = stanza;
				delay = (delay and delay.attr.stamp);
			};
			local ret = room:event(stanza.name, event);
			return ret or (stanza.name == "message") or nil;
		end
	end, 500);
	
	function stream:join_room(jid, nick)
		if not nick then
			return false, "no nickname supplied"
		end
		local room = setmetatable({
			stream = stream, jid = jid, nick = nick,
			subject = "",
			occupants = {},
			events = events.new()
		}, room_mt);
		self.rooms[jid] = room;
		local occupants = room.occupants;
		room:hook("presence", function (presence)
			local nick = presence.nick or nick;
			if not occupants[nick] and presence.stanza.attr.type ~= "unavailable" then
				occupants[nick] = {
					nick = nick;
					jid = presence.stanza.attr.from;
					presence = presence.stanza;
				};
				local x = presence.stanza:get_child("x", xmlns_muc .. "#user");
				if x then
					local x_item = x:get_child("item");
					if x_item and x_item.attr then
						occupants[nick].real_jid    = x_item.attr.jid;
						occupants[nick].affiliation = x_item.attr.affiliation;
						occupants[nick].role        = x_item.attr.role;
					end
					--TODO Check for status 100?
				end
				if nick == room.nick then
					room.stream:event("groupchat/joined", room);
				else
					room:event("occupant-joined", occupants[nick]);
				end
			elseif occupants[nick] and presence.stanza.attr.type == "unavailable" then
				if nick == room.nick then
					room.stream:event("groupchat/left", room);
					self.rooms[room.jid] = nil;
				else
					occupants[nick].presence = presence.stanza;
					room:event("occupant-left", occupants[nick]);
					occupants[nick] = nil;
				end
			end
		end);
		room:hook("message", function(msg)
			local subject = msg.stanza:get_child("subject");
			if subject then
				room.subject = subject and subject:get_text() or "";
			end
		end);
		local join_st = presence({to = jid.."/"..nick})
			:tag("x",{xmlns = xmlns_muc}):reset();
		-- Is this a good API for adding stuff etc?
		local ok, err = self:event("pre-groupchat/joining", join_st);
		if ok then
			self:send(join_st)
			self:event("groupchat/joining", room);
		end
		return room;
	end

	stream:hook("presence-out", function(presence)
		if not presence.attr.to then
			for _, room in pairs(stream.rooms) do
				room:send(presence);
			end
			presence.attr.to = nil;
		end
	end);
end

function room_mt:send(stanza)
	if stanza.name == "message" and not stanza.attr.type then
		stanza.attr.type = "groupchat";
	end
	if stanza.attr.type == "groupchat" or not stanza.attr.to then
		stanza.attr.to = self.jid;
	end
	self.stream:send(stanza);
end

function room_mt:send_message(text)
	self:send(st.message():tag("body"):text(text));
end

function room_mt:set_subject(text)
	self:send(st.message():tag("subject"):text(text));
end

function room_mt:leave(message)
	self.stream:event("groupchat/leaving", room);
	self:send(st.presence({type="unavailable"}));
end

function room_mt:admin_set(nick, what, value, reason)
	self:send(st.iq({type="set"})
		:query(xmlns_muc .. "#admin")
			:tag("item", {nick = nick, [what] = value})
				:tag("reason"):text(reason or ""));
end

function room_mt:set_role(nick, role, reason)
	self:admin_set(nick, "role", role, reason);
end

function room_mt:set_affiliation(nick, affiliation, reason)
	self:admin_set(nick, "affiliation", affiliation, reason);
end

function room_mt:kick(nick, reason)
	self:set_role(nick, "none", reason);
end

function room_mt:ban(nick, reason)
	self:set_affiliation(nick, "outcast", reason);
end

function room_mt:event(name, arg)
	self.stream:debug("Firing room event: %s", name);
	return self.events.fire_event(name, arg);
end

function room_mt:hook(name, callback, priority)
	return self.events.add_handler(name, callback, priority);
end