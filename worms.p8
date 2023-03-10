pico-8 cartridge // http://www.pico-8.com
version 41
__lua__
-- main

frame = 0
sprite_shift = 0 -- w_walk_ctrl()
nextid = 0

function newobj(x,y,vx,vy,spr,r,no_collide)
 nextid+=1
 return {
  id=nextid,
  r=r, -- body radius
	 x=x,y=y, -- pos
	 vx=vx,vy=vy, -- velocity
	 dx=0,dy=0, -- delta p accum
	 thrst=0, -- horiz.walk thrust
	 look=1, -- right or left?
	 spr=spr,
	 grnd=false, -- on ground?
	 no_collide=no_collide,
	 last_action=time(),
	 text_col = 7,
	 text_end_time = 0,
	 bounce=0
	 }
end

-- 16-bit safe range check for range up to 181
-- faster than using dist too
function is_in_range(x0,y0,x1,y1,range)
 if range>181 then
  return false -- calc not guaranteed
 end 
 
 local dx = abs(x1-x0)
 local dy = abs(y1-y0)
 
 if dx>range or dy > range then
  return false
 end
 
 return dx*dx+dy*dy < range*range
end

-- if dx or dy > 181 the result
-- is approx but better than
-- 16-bit errors
function dist(x0,y0,x1,y1)
 local dx = abs(x1-x0)
 local dy = abs(y1-y0)
 if dx>181 or dy>181 then
  if dx>16383 or dy>16383 then
   return 32767
  end 
  return dx+dy -- manhattan
 end
 local sqr=dx*dx+dy*dy 
 return sqrt(sqr)
end

function _init()
 b_init()
 
 g_state = g_state_menu
end

function clear(tbl)
 while #tbl>0 do del(tbl,tbl[1]) end
end

function _update()
 frame+=1
 if frame==30000 then frame = 0 end
 --if frame%10 > 0 then return end
 
 if g_state == g_state_victory then
  g_victory_update()
 elseif g_state == g_state_turn_end then
  g_turn_end_update()
 elseif g_state == g_state_turn then
  g_turn_update()
 elseif g_state == g_state_menu then 
	 mnu_update() 
 end
end

function _draw()
	cls(0)
	if g_state == g_state_menu then
	 mnu_draw()
	else
 	draw_sea()
  l_draw() -- level
 	foreach(bodies, p_draw)
  r_draw() -- particles
 	u_draw() -- ui
 end	
 	
 print(stat(1)*100\1 .."%", 0, 0)	
 if debug then print(debug) end
end

function draw_sea()
 local v = c_wrld_to_scr({x=0,y=128})
 
 rectfill(0,v.y,128,v.y+128,1)
end
-->8
-- level : l

-- level size in cells
grd_w = 32 -- grid width
grd_h = 16 -- grid height
 
-- level size in pxls
lvl_w = grd_w * 8
lvl_h = grd_h * 8

stride = lvl_w / 2

-- copy destructible level
-- in mem from map:
-- 0x8000 is normal map pixels
-- 0xc000 is 2x zoomed out map
function l_load_lvl(lvl, mine_cnt)
 memset(0x8000,0,stride * lvl_h)
 local spwn_pnts = {}
 local tx_offs = (lvl%4)*32
 local ty_offs = (lvl\4)*16
 local mine_pnts = {}
 
 -- copy map to mem
 for ty = 0,grd_h-1 do
 	for tx = 0,grd_w-1 do
 	
 	 local offs_x = tx<<2
 	 local offs_y = ty<<3
 	 
 		local t = mget(tx_offs+tx,
 		 ty_offs+ty)
 		local p = {x=tx*8+4,y=ty*8+4}
 		
 		if t == 1 then -- spawn pnt
 		 add(spwn_pnts, p)
 		elseif t == 40 then -- mine
 		 if rnd(1) > 0.5 then
  		 add(mine_pnts, p)
  		end 
 		else 
 		 -- copy tile pxls to mem
 	 	local spr_addr = 512 * (t \ 16) + 4 * (t % 16)
	 	 local y_addr = offs_y * stride

  		for y = 0,7 do
 	 	 memcpy(0x8000+y_addr+offs_x, spr_addr, 4)
  		 spr_addr += 64
  		 y_addr += stride
 	 	end
 		end 		
 	end
 end
 
 l_spawn_mines(mine_pnts, mine_cnt)
 
 return spwn_pnts
end

function l_spawn_mines(pnts, cnt)
 for i=0,cnt-1 do
  if #pnts == 0 then break end
  local p = rnd(pnts)
  m_spawn_mine(p)
  del(pnts, p)
 end
end

function l_draw()
 if c_zoomed then
  l_draw_overview()
 else
  l_draw_normal()
	end
end

function l_draw_overview()
 -- poorman's resampler to 1/2 size
 -- per 4 pxls we take the first 2
 -- (= per 2 bytes we take the first)
 local scr_addr = 0x6000+31*64
 local lvl_addr = 0x8000
 for y=0,63 do
  for x=0,63 do
   poke(scr_addr+x,peek(lvl_addr))   
   lvl_addr += 2
  end 
  scr_addr += 64
  lvl_addr += 128
 end
end

function l_draw_normal()
 -- cull y:
 local y0 = cam_y
 local y1 = cam_y+127
 if y0 >= lvl_h or y1 < 0 then return end
 y0=max(0, y0)
 y1=min(lvl_h-1, y1)

 -- cull x:
 local x0 = cam_x
 local x1 = x0 + 127
 if x0 >= lvl_w or x1 < 0 then return end
 x0=max(0, x0)
 x1=min(lvl_w-1, x1)
 
 local len = (x1-x0+1)\2
 
 -- render level pixels
 local scr_addr = 0x6000
  + ((y0-cam_y)<<6) 
  + (x0-cam_x)\2
  
 local wrl_addr = 0x8000
	 + (y0 << 7) + x0\2
 
	for y = y0,y1 do
	 memcpy(scr_addr,wrl_addr,len)	 
	 scr_addr += 64
  wrl_addr += stride
	end
end

-- is obstacle?
function l_obstacle(x,y, except1, except2)
 return l_terrain_obstacle(x,y) 
  or l_worms_obstacle(x,y, except1, except2)
end

function l_terrain_obstacle(x,y)
 x \= 1
 y \= 1
 if x<0 or x>=lvl_w or y<0 or y>=lvl_h then
  return false
 end
 local v = peek(0x8000+(y<<7)+(x>>1))

 -- left or right pxl?
 if x%2 == 0 then
  return v\16 > 0
 else
  return v%16 > 0
 end
end

function l_worms_obstacle(x,y, except1, except2)
 for w in all(worms) do
  if w!=except1 and w!=except2 and is_in_range(w.x,w.y, x,y, w.r) then
   return true
  end
 end
 return false
end

-- removes terrain at x,y,radius
function l_destroy(x,y,r)
 local d = r*2+1
 local x0 = x\1 - r
 local y0 = y\1 - r
 local x1 = x0+d
 local y1 = y0+d
 
 -- coerce to terrain bounds
 x0 = min(lvl_w-1,max(0,x0))
 y0 = min(lvl_h-1,max(0,y0))
 x1 = min(lvl_w-1,max(0,x1))
 y1 = min(lvl_h-1,max(0,y1))
 
 local addr = 0x8000+(y0<<7)
 
 for yi=y0,y1 do
  for xi=x0,x1 do
   if dist(xi,yi,x,y) <= r then
    local msk = xi%2==0 and 0xf0 or 0x0f
    poke(addr+xi\2,
     band(peek(addr+xi\2), msk))
	  end
  end 
  addr += stride
 end
 
 addr = 0xc000+(y0<<6)+(x0>>2)
 for i=y0,y1 do
  memset(addr,0,(x1-x0+2)/4)
  addr += stride\2
 end
end
-->8
-- worms : w

worms = {}
-- w_p = player possessed worm
-- w_aiming
charge = 0 -- max 49

w_last_weap_switch = 0

function w_player_ctrl()
 if w_p.dead then
  g_end_turn()
  return
 end

 -- toggle aim/walk
 if not btn(???????) then
  w_cross_turn_aim_safe = true
 end 
 w_aiming = btn(???????) 
  and w_p.grnd 
  and g_state == g_state_turn
  and w_cross_turn_aim_safe

 if w_aiming then
  ???_ready = false
  c_zoom_in()
  w_shoot_ctrl()  
 else
  charge = 0
  w_walk_ctrl()
 end
end

???_prev=true
???_start = 0
???_ready = true
-- player ctrl in walk mode
function w_walk_ctrl()

 if not btn(???) then ???_ready = true end
 -- start ???-down tracking
 if ???_ready and 
   not ???_prev and btn(???) then 
  ???_start = time() 
 end

 -- keyup
	if ???_prev and not btn(???) then
  local presstime=time()-???_start	
  if presstime < 0.5 then
   --short press: jump
   if w_p.grnd then 
    w_p.vy = -2 
    w_p.vx = w_p.look*1.5
    w_p.grnd = false
   end
  end
	end
	
	if ???_ready and ???_prev and btn(???) then
  local presstime=time()-???_start
  if presstime > 0.5 then
   c_toggle_zoom()
   ???_ready = false
  end 
	end
	
	-- switch weapon
	if btnp(??????) or btnp(??????) then
	 if time() - w_last_weap_switch < 3 then
	  local step = btnp(??????) and -1 or 1
	 	local nxt = (#b_weap + w_p.weapon.id+step) % #b_weap
	  w_p.weapon = b_weap[nxt+1]
	 end 
	 -- bring up menu without actual switch if long ago
	 w_last_weap_switch = time()
	end
 
 -- walk? (during turn and first 5s of turn-end
 w_p.thrst = 0
 if (g_state == g_state_turn or g_state == g_state_turn_end and time() < turn_end_time + 5)
  and (btn(??????) or btn(??????)) then
  w_p.thrst = 0.3 -- walk speed
  if btn(??????) then w_p.thrst *= -1 end
 end
 
 ???_prev = btn(???)
end

-- player ctrl in shoot mode
function w_shoot_ctrl()
 -- change aim?
 if w_p.weapon.aimed then
  if btn(??????) then w_p.aim=min(0.25,w_p.aim+0.0125) end
  if btn(??????) then w_p.aim=max(-0.25,w_p.aim-0.0125) end
 end
 
 -- shoot/charge?
 if w_p.weapon.aimed then
  w_shoot_with_charge()
 else
  w_shoot_without_charge()
 end
 
 -- toggle look side?
 if btn(??????) then
  w_p.thrst = 0.001
 elseif btn(??????) then 
  w_p.thrst = -0.001
 end
end

function w_shoot_with_charge()
 if btn(???) and charge > -1 and charge<49 then
  charge = min(49, charge+1)
 elseif charge > 0 then
  charge*=0.2 // abuse this var
  b_fire(w_p.weapon, 
   w_p.x, w_p.y, 
   cos(w_p.aim) * charge * w_p.look,
   sin(w_p.aim) * charge,
   w_p)
   
  g_end_turn() 
  
  charge = -1 -- disable successive charging
 end
 if not btn(???) then
  charge = 0
 end
end

function w_shoot_without_charge()
 if btnp(???) then
  b_fire(w_p.weapon, 
   w_p.x, w_p.y, 
   0,0, w_p)
   
  g_end_turn() 
 end
end

function w_update(w)	

 if w.flashtime > 0 then
  w.flashtime -= 1
 end

 -- hurt from fall
	if w.collide and w.collide_force > 3 then
	 w_hurt(w, w.collide_force * 2)
	end
	if w.out_of_arena then
  t_kill(w, true)
	end
	
 -- look-direction
 if w.thrst > 0 then
  w.look = 1
 end
 if w.thrst < 0 then
  w.look = -1
 end

 -- which sprite?
 if w.flashtime % 8 > 3 then
  w.spr = 2
 elseif w.grnd and abs(w.thrst) > 0.1 then
  w.spr = 3 + frame\10 % 2
 else
  w.spr = 1
  if w.vy < 0 then 
  	w.spr = 5 
  elseif w.vy > 1 then
   w.spr = 6 
  end
 end	
end

function w_hurt(w, amount)
  amount \= 1
  if amount == 0 then return end
  
  w.health -= amount
  if w.health < 0 then
   t_kill(w, w.out_of_arena)
  end
  w.flashtime = 60
  r_emit(w.x-10,w.y-5,-0.5,0,0,40,8,amount)

	 if w_p == w then
	  g_end_turn() -- end turn when your worm is hurt  
	 end 
end
-->8
-- camera : c
cam_x=0
cam_y=0
cam_x_int=0
c_zoom = 1
c_zoomed = false

cam_speed_x = 8

c_chase = false

target={x=0,y=0}

function c_update()
 -- select camera target 
 if g_state == g_state_turn then
  target = {x=w_p.x, y=w_p.y}
  local extra = w_aiming and 30 or 10
 	target.x += (w_p.look < 0) and -extra or extra
 elseif g_state == g_state_turn_end then
  if time() < w_p.last_action+0.5 then
   target={x=w_p.x, y=w_p.y}
  elseif g_latest_active then
   target={
    x=g_latest_active.x, 
    y=g_latest_active.y}
  end
	end
	 
	local tx = target.x-64
	local ty = target.y-64 
	 
 local dist = abs(tx-cam_x_int) 
 
  if c_chase or (g_state == g_state_turn and w_p.thrst == 0 and w_p.grnd) then
   local speed = dist > 60 and cam_speed_x * 5 or cam_speed_x
   if tx > cam_x_int then
    cam_x_int += min(speed,dist)
   else
    cam_x_int -= min(speed,dist)
   end
   if dist < 2 then
    c_chase = false
   end
  else
   local max = g_state == g_turn_end and 100 or 40
   if dist > max then
    c_chase = true
   end
  end
 
 -- vertical:
 
 dist = abs(ty - cam_y)
 if dist > 10 then
  if cam_y < ty then
   cam_y += ty-cam_y-10
  else
   cam_y -= cam_y-ty-10
  end
 end

 -- round to even (for pixel memory)
	cam_x = cam_x_int \ 2 * 2
end

function c_toggle_zoom()
 if c_zoomed then
  c_zoom_in()
 else
  c_zoom_out()
 end
end

function c_zoom_in()
 c_zoomed = false
	c_zoom = 1
	sprite_shift = 0
end

function c_zoom_out()
 c_zoomed = true
	c_zoom = 2
	sprite_shift = 8
end

-- world 2 scr coords
-- for any { x,y }
function c_wrld_to_scr(v)
 if c_zoomed then
  return {
   x = v.x\2,
   y = v.y\2 + 31
  }
 else
  return {
   x = v.x - cam_x,
   y = v.y - cam_y
  }
 end
end
-->8
-- physics : p

bodies = {}

function p_integrate(b)
 local last_x=b.x
 local last_y=b.y

 b.collide = false

 -- fell in water?
 if b.y >= 160 then 
  b.collide = true 
  b.collide_force = 100
  b.out_of_arena = true
  return
 end

 -- on ground?
 b.grnd = l_obstacle(b.x, b.y+b.r+1, b, b.no_collide)

 -- push out of ground (horiz slope)
	while l_obstacle(b.x, b.y+b.r, b,b.no_collide) 
	   or l_obstacle(b.x, b.y+b.r-1, b,b.no_collide) do
	 b.y -= 1
	end
	
	-- gravity
 if b.grnd then
  b.vx /= 2 	
 elseif b.y < 128 then
  b.vy += 0.15
 else
  // landed in water
  b.vy = 0.5 
  b.vx = 0
	end

 -- accumulate distance to move
 b.dx += b.vx + b.thrst
	b.dy += b.vy
		
	-- ??????
	while b.dx>=1 do
	 if l_obstacle(b.x+1, b.y, b,b.no_collide) then
 	  b.collide_force = b.vx
    b.dx = -b.dx * b.bounce
 	  b.vx = -b.vx * b.bounce
 	  b.collide = true
		 else 
		  b.x += 1
		  b.dx -= 1
		 end
	end
	
	-- ??????
	while b.dx<=-1 do
	 if l_obstacle(b.x-1, b.y, b,b.no_collide) then
 	  b.collide_force = b.vx
    b.dx = -b.dx * b.bounce
 	  b.vx = -b.vx * b.bounce
 	  b.collide = true
		 else 
		  b.x -= 1
		  b.dx += 1
		 end
	end
	
	-- ??????
	while b.dy>=1 do
	 if l_obstacle(b.x, b.y+b.r+1, b,b.no_collide) then
 	  b.collide_force = b.vy
    b.dy = -b.dy * b.bounce
 	  b.vy = -b.vy * b.bounce
 	  if abs(b.vy) < 0.5 then
 	   b.vy = 0
 	  end
 	  b.vx *= b.bounce--grnd friction
 	  b.collide = true
		 else 
		  b.y += 1
		  b.dy -= 1
		 end
	end
	
	-- ??????
	while b.dy<=-1 do
	 if l_obstacle(b.x, b.y-b.r, b,b.no_collide) then
 	  b.collide_force = b.vy
    b.dy = -b.dy * b.bounce
 	  b.vy = -b.vy * b.bounce
 	  b.vx /= 2
 	  b.collide = true
		 else 
		  b.y -= 1
		  b.dy += 1
		 end
	end
	
	if last_x != b.x or last_y != b.y then
	 b.last_action = time()
	end
end

function p_draw(b)
  local v = c_wrld_to_scr(b)
  -- originally all items had
  -- zoomout equivalents, 
  -- but weapons are 
  -- never visible in zoomout
  -- anymore
  spr(b.spr+sprite_shift,
   v.x-3, v.y-3,
   1,1,
   b.look<0,
   false
   )
  if b.text and time() <= b.text_end_time then   
    print(b.text, v.x, v.y-15, b.text_col)
  end 
end
-->8
-- bullets/weapons: b

b_dir2spr = {0,1,2,1,0,3,4,3}

bullets = {}

b_weap = {}

function b_add_wp(name,
 aimed,directional,
 spr_w,spr,
 bounce)
 
 local id = #b_weap
 local w = { id=id, 
    name=name,
    aimed=aimed,
    spr_w=spr_w, -- weapon on worm body
    spr=spr, -- bullet+icon
    bounce=bounce,
    directional=directional -- sprite/dir?
     }
 add(b_weap, w)
    
 return w
end

function b_init()
 b_bazooka = b_add_wp("bazooka",true,true,16,17, 0)
 b_grenade = b_add_wp("grenade",true,true,32,33, 0.6)
 b_clusterbomb = b_add_wp("cluster bomb",true,true,48,49,0.6)
 b_cluster = {spr=54,bounce=0,directional=false} -- comes out of clusterbomb
 b_dynamite = b_add_wp("dynamite",false,false,38,22, 0.2)
 b_firepunch = b_add_wp("fire punch",false,false,24,8, 0)
 b_skipturn = b_add_wp("skip turn",false,false,0,23, 0)
end
	
function b_fire(w, x,y,vx,vy,shooter)
 if w == b_skipturn then
  -- do nothing
  return
 elseif w == b_firepunch then 
  b_do_firepunch(w_p)
  return
 elseif w == b_dynamite then
  x += w_p.look * 4
 end

 b_launch_bullet(w, x,y, vx,vy, shooter)

end

function b_do_firepunch(w)
 for b in all(bodies) do
  if b != w then -- not yourself!
   local dx = abs(w.x - b.x)
   local dy = b.y - w.y
   if dy >= -4 and dy < 8
     and dx >1 and dx < 12 then
    b.vx = 2*w.look
    b.vy = -3
   end 
  end
 end
 w.vy = -2
end

function b_launch_bullet(w, x,y, vx,vy, shooter)
 local b = newobj(
   x,y,
   vx,vy,
   w.spr, 2, 
   shooter)
 b.bounce = w.bounce
 b.weapon = w
 b.start_time = time()
 
 add(bodies, b)
	add(bullets, b)
end

function b_update_bazooka(b,r,dmg)
 if b.collide then
 	 b_despawn(b)
   b_explosion(b.x,b.y, r, dmg)
	end
end

function b_update_grenade(b,r,countdown,dmg)
 local time_remain = b.start_time + countdown - time()
 if time_remain > 0 then
  b.text = time_remain\1+1
  b.text_end_time = b.start_time+5
  b.last_action = time() -- keep cam on me
  return false
 else
  b_despawn(b)
  b_explosion(b.x, b.y, r, dmg)
  return true
 end
end
	
function b_update(b)
 if b.weapon == b_bazooka then
  b_update_bazooka(b,12,50)

 elseif b.weapon == b_grenade then
  b_update_grenade(b,12,4,50)
  
 elseif b.weapon == b_clusterbomb then
  if b_update_grenade(b,8,3,30) then
   for i=1,7 do
    b_launch_bullet(b_cluster, b.x,b.y,
     b.vx+rnd(2)-1, -3-rnd())
   end
  end
 elseif b.weapon == b_cluster then
  b_update_bazooka(b,5,15)
  
 elseif b.weapon == b_dynamite then
  b_update_grenade(b,14,4,75)
 end

 if b.vx != 0 then b.look = b.vx end

 -- set sprite 
 if b.weapon.directional then
  if b.vx != 0 or b.vy != 0 then
 	 local x = abs(b.vx)
 	 local a = ((atan2(x,b.vy)*8+0.5)\1)%8 
 		b.spr=b_dir2spr[a+1]+b.weapon.spr
 	end
 else
  b.spr = b.weapon.spr
 end
end

function b_despawn(b)
 b.dead = true
 del(bodies,b)
 del(bullets,b)
end

function b_explosion(x,y,r,pwr)
 local hr = r/2
 
 -- small smoke parts:
 for i=1,8 do
  local a = rnd(32)/32
  r_emit(
   x+cos(a)*(hr+rnd(hr)), 
   y+sin(a)*(hr+rnd(hr)),
   -0.5, -- vy
   2+rnd(hr),-0.1, --radius 
   20+rnd(40), -- lifetime
   5+rnd(3)) -- color
 end
 
 -- big flash:
 r_emit(x, y,0, r*2,-3, 4,9)
 l_destroy(x,y, r)
 
 b_throw_bodies(x,y,r*3,pwr)
end

function b_throw_bodies(x,y,r,pwr,except)
 y += 5 // lower epicenter=more upwards throwing
 
 for b in all(bodies) do
  if b != except then
   local d = dist(b.x,b.y, x,y)
   if d<r then
    local force_pct = (r-d)/r -- [0..1]

				if d>0.01 then   
     b.vx = (b.x - x)/d * force_pct*7
     b.vy = (b.y - y)/d * force_pct*7
    end

    -- damage it
    if b.health then
     w_hurt(b, force_pct*pwr)
    end
   end
  end 
 end
end
-->8
-- ui : u

function u_draw() 
 if w_aiming then
  u_draw_crosshair()
  u_draw_chargebeam()
 end
 foreach(worms, v_draw_healthbar)
 if g_state == g_state_turn then
  u_draw_marker()
  u_draw_weapon()
  u_draw_weapon_panel()
 end
 u_draw_timer()
end

function u_draw_timer()
 if g_state == g_state_turn then
  local t = (time() - turn_start_time)\1
  if t < 3 then
   spr(123+t,60,30)
  else
   if t == 3 then
    spr(126,54,30,2,1)
   end 
   if t >= 3 then
    local col = 11
    if t > (turn_time+3-10) then
     if frame % 8 > 4 then
      return
     end
     col = 8
    end
    print(turn_time-t+3, 60,1, col)
   end 
  end 
 end
end

function u_draw_weapon()
 if not c_zoomed and abs(w_p.vx+w_p.thrst) < 0.1 then
  local pnt = c_wrld_to_scr(w_p)
  local x = w_p.weapon == b_dynamite and 7 or 0
  x *= w_p.look
  spr(w_p.weapon.spr_w, pnt.x-3+x, pnt.y-2, 
   1,1, w_p.look<0, false)
 end
end

weapon_panel_y = 10
function u_draw_weapon_panel()
 local t = w_last_weap_switch+4-time()
 if t > 0 then
  local x = 2
  if t < 1 then
   x = -40 + t*40 + 2
  end 

  rectfill(x,weapon_panel_y,x+9,weapon_panel_y+#b_weap*10,2)
  rect(x-1,weapon_panel_y-1,x+10,weapon_panel_y+#b_weap*10,5)

  for w in all(b_weap) do
   local y = weapon_panel_y+w.id*10
   spr(w.spr,x+1,y+1)
   if t>1 and w == w_p.weapon then
    print(w.name, x+13, y+3, 7)
   end
  end
  local y = weapon_panel_y+w_p.weapon.id*10
  rect(x-1,y-1,x+10,y+10, t_get_team_color(w_p.team))
 end
end

function u_draw_crosshair()
 if not w_p.weapon.aimed then
  return
 end
 
 local dir_x = cos(w_p.aim)*w_p.look
 local dir_y = sin(w_p.aim)
 local pnt = c_wrld_to_scr(w_p)
 
 spr(7+sprite_shift,-- crosshair
  pnt.x-3 + dir_x*15, 
  pnt.y-3 + dir_y*15)
end

function u_draw_chargebeam()
 if charge > 0 then
  local dir_x = cos(w_p.aim)*w_p.look
  local dir_y = sin(w_p.aim)
  local pnt = c_wrld_to_scr(w_p)

  for i=2,charge\2,2 do
   circfill(
    pnt.x + (dir_x*i)\c_zoom,
    pnt.y + (dir_y*i)\c_zoom,
    (1+i\4)\c_zoom,
    max(8,10-i\8))
  end
 end
end

function v_draw_healthbar(w)
 local p = c_wrld_to_scr(w)
 local col = 8 
   + w.health\26 -- 0..3
 p.y -= 7
 p.x -= 3
 
 local wdth = 7
 local teamcol = t_get_team_color(w.team)
 rectfill(p.x-1, p.y-1, p.x+wdth+1,p.y+1, teamcol) 
 line(p.x, p.y, p.x+wdth, p.y, 13)
 line(p.x, p.y, p.x+w.health\13, p.y, col)
end

function u_draw_marker()
 local p = c_wrld_to_scr(w_p) 
 spr(39, p.x-3, p.y - 17 + sin(frame%40/40)*1.5)
end
-->8
-- particles : r

parts = {}

function r_emit(x,y,vy,r,vr,life,col,text)
 add(parts,{
 x=x,y=y, vy=vy,
 r=r, vr=vr,
 l=life, -- lifetime
 text=text,
 col=col}) -- color
end

function r_update()
 if #parts == 0 then return end
 
 for i=#parts,1,-1 do
  local prt = parts[i]
  prt.l -= 1

  if prt.l >= 0 then
   prt.y += prt.vy
   prt.r += prt.vr
  else
   del(parts, prt)
  end
 end
 
 -- remove dead particles
 for i=#parts,1,-1 do
  local prt = parts[i]
  
 end
end

function r_draw()
 for i=1,#parts do
  local prt = parts[i]
  local p = c_wrld_to_scr(prt)
  
  if prt.text then
   print(prt.text, p.x, p.y, 
    prt.col)
  else
   circfill(p.x, p.y,
    prt.r\c_zoom,
    prt.col)
  end
 end
end
-->8
-- teams : t

teams = {}

function t_init()
 clear(teams)
 team_won = -1
 for i=0,1 do
  teams[i] = {worms={}}
 end
end

function t_spawn(x,y,team)
 local w = newobj(x,y,0,0,1,4,nil)
 w.bounce = 0.1
 w.health = 100
 w.team = team
 w.flashtime = 0
 w.weapon = b_bazooka
 w.aim = 0
 
 add(worms, w)
 add(bodies, w)
 add(teams[team].worms, w)
 print(team)
 return w
end

function t_kill(w,instant)
 w.dead = true
 del(worms,w)
 del(bodies,w)
 add(bodies,--spawn tombstone
    newobj(w.x,w.y,w.vx,-2,55,4))
    
 for i=0,1  do
  local team=teams[i]
  local live_cnt = 0
  for w in all(team.worms) do
   if not w.dead then 
    live_cnt+=1
   end
  end
  
  if live_cnt == 0 then
   g_victory((i+1)%2)
  end
 end
end

function t_get_team_color(team)
 return team==1 and 3 or 14
end
-->8
-- gamestate : g

g_state = 0

g_state_turn = 1
g_state_turn_end = 2
g_state_victory = 3
g_state_menu = 4

turn_time = 40

g_last_action = 0

team_won = -1
turn_start_time = 0
turn_end_time = 0

function g_start_game(lvl,mine_cnt)
 clear(mines)
 clear(bodies)
 clear(worms)
 clear(bullets)
 clear(parts)
 t_init()
 
	local sps = l_load_lvl(lvl, mine_cnt)
	local sps = l_load_lvl(lvl, mine_cnt)

 local team=0
 while #sps>0 do
  local sp = rnd(sps)
  t_spawn(sp.x,sp.y,team)
  team = (team+1)%2
  del(sps,sp)
 end
 
 g_next_turn()
end

function g_victory(team)
 team_won = team
 r_emit(50,60,0,1,0,1000,11,"team won: "..team)
end

-- starts the turn-end sequence
-- cam follows remaining action
-- until no more action
function g_end_turn()
 g_state = g_state_turn_end
 turn_end_time = time()
end

function g_turn_end_update()
 -- detect action:
 for b in all(bodies) do
  if not b.dead and not (b.is_mine and not b.triggered) and b.last_action > g_last_action then
   g_last_action = b.last_action
   g_latest_active = b
  end
 end
 
 -- wait until no more action
 if time() - g_last_action >= 3 then
  g_state = g_state_turn
  g_next_turn()
 end
 
 w_player_ctrl() 
 g_scene_tick()
end

function g_victory_update()
 c_zoom_out()
 g_scene_tick()
end

function g_turn_start()
 g_state = g_state_turn
 
 -- this prevents shooting immediately
 -- after turn ended with skip-turn
 w_cross_turn_aim_safe = false
 turn_start_time = time()
 w_last_weap_switch = time()
 
 r_emit(w_p.x-9,w_p.y-4,-0.5,1,0,50, 1,"my turn!")
 r_emit(w_p.x-10,w_p.y-5,-0.5,1,0,50,  t_get_team_color(w_p.team),"my turn!")
end

function g_turn_update()
 if time() - turn_start_time >= turn_time+4 then
  g_next_turn()  
 end
 w_player_ctrl() 
 g_scene_tick()
end

-- start next turn
function g_next_turn()
 local team = w_p
  and teams[(w_p.team+1)%2]
  or teams[0]
 
 if not team.curr then
  team.curr = team.worms[1]
 else
  local found = false
  local i = 1
  while true do
   local w = team.worms[i]
   if not found then
    if w == team.curr then
     found = true
    end 
   elseif not w.dead then
    team.curr = w
    break
   end
   
   i = ((i+1) % #team.worms)+1
  end
  
 end
 
 if c_zoomed then
  c_toggle_zoom()
 end
 
 w_p = team.curr
 g_turn_start()
end

-- update physics/anims/camera
function g_scene_tick()
 foreach(worms, w_update)
 foreach(bodies, p_integrate)
 foreach(bullets, b_update)
 r_update() // particles
 m_update() // mines

 c_update() -- camera
end
-->8
-- mines : m

mines = {}

function m_spawn_mine(p)
 local mine = newobj(p.x,p.y,
  0,0, 128, 2)
 mine.is_mine = true
 add(bodies,mine)
 add(mines,mine) 
end

m_mine_range=12
function m_update()
 foreach(mines, m_check_trigger)
 
 for i = #mines,1,-1 do
  m_upd_mine(mines[i])
 end
end

function m_upd_mine(m)
 if m.triggered then
  m.last_action = time()
  local remain = m.text_end_time - time()
  if remain <= 0 then
   del(bodies,m)
   del(mines,m)
   b_explosion(m.x,m.y, 14, 75)
  else
   m.text = remain\1+1
   m.spr = frame%10>5 and 128 or 129
  end
 end
end

function m_check_trigger(m)
 if m.triggered then
  return
 end

 for w in all(worms) do
  if is_in_range(m.x,m.y, 
   w.x,w.y, m_mine_range) then
    m.triggered = true
    m.last_action = time()
    m.text_end_time = time()+4
  end
 end 
end
-->8
-- mainmenu: mnu

mnu_blink = 5
mnu_blink_fr = 0

options = {}


add(options, {i=1,n="play"})
add(options, {i=2,n="level: ", v=1, min=1, max=8})
add(options, {i=3,n="mines: ", v=3, min=0, max=6})

function mnu_update()
 if not mnu_sel_option then
  mnu_sel_option = options[1]
 end
 
 -- up/dn
 if btnp(??????) or btnp(??????) then
  local chng = btnp(??????) and 1 or -1
  local nxt = (mnu_sel_option.i-1+#options+chng) % #options
  mnu_sel_option = options[nxt+1]
 end
 
 -- change value
 if btnp(??????) or btnp(??????) and mnu_sel_option.v then
  local o = mnu_sel_option
  local chng = btnp(??????) and 1 or -1
  o.v = max(o.min, min(o.max, o.v+chng))
 end
 
 if btnp(???) or btnp(???????) and mnu_sel_option == options[1] then
   g_start_game(options[2].v-1, options[3].v)
 end
 
end

function mnu_draw()
 mnu_draw_logo()
 mnu_draw_menu()
end

function mnu_draw_menu()
 local y=40
 for option in all(options) do
  if option == mnu_sel_option then
   spr(7, 35, y-1)
  end
  if option.v then
   print(option.n..option.v, 48, y)
  else
   print(option.n, 48, y)
  end 
  y += 12
 end
end

function mnu_draw_logo()
 spr(168,30,10,8,2)
 if mnu_blink < time() then
  mnu_blink = time()+1+rnd(5)
  mnu_blink_fr = 5
 end
 if mnu_blink_fr > 0 then
  spr(31,85,5)
  mnu_blink_fr -= 1
 else
  spr(1,85,5)
 end
end
-->8
-- todo

-- bug: no victory when all killed
-- bug: cam should not flicker between actions
-- worm burrowed after fall
-- uzi
-- show total team health
-- show input button help?
-- barrel + fire particles
-- consume weapon amnt
-- more particles (fall, shoot)
-- die in sequence at endturn
-- show "oops" when turn over without dmg

-- egypt, snowworld
__gfx__
000000000000fff00000888000000000000fff000007f70000000000009990000ff0000000000000000000000000000000000000000000000000000000000000
0000000000077f77000778770000fff000f77f700071f1700ff00000090909000f088f0000000000000000000000000000000000000000000000000000090000
0000000000071f1700071817000f77f700f71f100077f770fffff00090090090000f8800000ff000000880000000ff00000ff000000f700000ff000000090000
0000000000077f7700077877000f71f100f77f7000fffff000fffff099979990000ff88000077000000770000000f700000f7000000ff000000ff00009909900
000000000000ffff00008888000f77f700fffff000fffff000f77f77900900900000ff0000fff0000088800000ffff0000fff00000fff000000f700000090000
0000000000fffff0008888800000ffff0fffff00000fff0000077f77090909000000ff000fff0000088800000f0ff00000ff000000f00000000ff00000090000
000000000ffffff0088888800ffffff0ffffff00000fff0000071f170099900000000ff000000000000000000000000000000000000000000000000000000000
00000000ff0fff0088088800ff0fff00f0fff00000fff0000000fff0000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000ee000056000000006600000005a09007f7000000888880000000000000000000000000000000000000000000000000000fff0
09915599000000000000ee00008998005110000000611600000500a00f000f0000800000000000000000000000000000000000000000000000000000000fffff
aa566aa1060dddf0000d890000188100511dd000000dd000000509097000007008000000000000000000000000000000000000000000000000000000000fffff
9911199151d1189800d118000011110000d1110000d11d0000882000f000000f00000000000000000000000000000000000000000000000000000000000fffff
0441114451111898001111000011110000111880001111000088200007f0000f000000000000000000000000000000000000000000000000000000000000ffff
00000000050111806d11100000011000000184200012210000882000000f00030000000000000000000000000000000000000000000000000000000000fffff0
0000000000000000511000000051150000002200002442000088200000030003000000000000000000000000000000000000000000000000000000000ffffff0
000000000000000005500000000550000000000000022000008820000003000000000000000000000000000000000000000000000000000000000000ff0fff00
09900000000990000005000000000000000000000007300000000000000000000000000000000000000000000000000000000000000000000000000000000000
56650000005665000000590000000500003b00000773b300050000000000a0000000000000000000000000000000000000000000000000000000000000000000
0736600005073660000036900073b05003b3b000063b350000500000000a7a000000000000000000000000000000000000000000000000000000000000000000
735360000073536000735360073b35690b353305065353000050000000a7aa900000000000000000000000000000000000000000000000000000000000000000
3b356000003b3560073b356003b353690053550500653000088200000009a9000000000000000000000000000000000000000000000000000000000000000000
0350000000b3535003b3506000353050006556900006650008820000000090000000000000000000000000000000000000000000000000000000000000000000
00000000000530000035000000055500000669000009905008820000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000008820000000000000000000000000000000000000000000000000000000000000000000000000000
04400000000440000005000000000000000000000008200000000000000000000000000000000000000000000000000000000000000000000000000000000000
566500000056650000005400000005000028000007828200000000000006d0000000000000000000000000000000000000000000000000000000000000060000
0826600005082660000026400082805002828000062825000002000000666d000000000000000000000000000000000000000000000000000000000000666000
8252600000825260008252600828256408252205065252000056500000666d000000000000000000000000000000000000000000000000000000000000060000
282560000028256008282560028252640252550500652000006550000006d0000000000000000000000000000000000000000000000000000000000000060000
025000000082525002825060002520500065264000066500000500000006d0000000000000000000000000000000000000000000000000000000000000000000
000000000005200000250000000555000006640000044050000000000006d0000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000d3355d00000000000000000000000000000000000000000000000000000000000000000
44544445000000e33000000000000000000000000000000000000000000000000000000000000000000000000000000000000000665444454454444544544445
55454445000003353300000000000000000000000000000000000000000000000000000000000000000000000000000000000000664544455545444555454445
4444555500000333433c000000000000000000000000000000000000000000000000000000000000000000000000000000000000466455554466666546666664
44454544000935434433000000000000000000000000000000000000000000000000000000000000000000000000000000000000666665666666666665561566
4454454400033544445440000000000000000000000000000000000000000000000000000000000000000000000000000000000066dd66666dd6666611561d6d
55444545003443455544333000300090003003000000000000000000000000000000000000000000000000000000000000000000dd44d66d6d6666661116dddd
4454445403344454445444303003003330303000000000000000000000000000000000000000000000000000000000000000000044544664666666dd66666611
4454445434544454445444533333333333333333000000000000000000000000000000000000000000000000000000000000000044544dd4d66dd717ddd6d1dd
ddd56ddd445445500005445400400040004000000000000000000000000000000000000000000000000000000000000000000000000000007dd715511ddd1ddd
dd55dddd445500000000545540400000000f000000000000000000000000000000000000000000000000000000000000000000000000000057155411111176dd
555ddddd5500000000000044040000000000000000000000000000000000000000000000000000000000000000000000000000000000000044445551111766d1
65665d555000000000000054000000000000000000000000000000000000000000000000000000000000000000000000000000000000000044454511117666d1
d56d5556000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004454111717666dd5
d5dd566d4000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000055471716666ddd55
dd556ddd5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000044566666dddd5554
ddd56ddd000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004455dddd15554454
44544445000000060000000000000000d65d5556d65d555600000000000000000000000000000000000000000000000000000000000000000000000000000000
554544450000666d00000000000000000d006d000d306d3000000000000000000000000000000000000000000000000000000000000000000000000000000000
444466650000dddd0000000000000000000000000030030000000000000000000000000000000000000000000000000000000000000000000000000000000000
65446d5600665d550000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000000000000000000000000
d5665555006d55560000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000000000000000000000000
d5dd566d06dd566d0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
dd556ddd6d556ddd00000000d0006600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
ddd56dddddd56ddd0000000055dd6d56000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
44546ddd00000006d000000000000000000000000000000000000000000000000000000000000000000000000177771001777710000171001777710017771077
5545dddd00000006dd50000000000000000000000000000000000000000000000000000000000000000000001710017117100171001771007100171071017177
44444ddd0000003d555d000000000000000000000000000000000000000000000000000000000000000000000100017100000171017171007100000071017117
44455d55000003656566000000000000000000000000000000000000000000000000000000000000000000000001771000001710000171007100000071001717
4454445600000656d56d500000000000000000000000000000000000000000000000000000000000000000000000017100017100000171007101777071001717
5544466d0006666dd5dd530000000000000000000000000000000000000000000000000000000000000000000100017100171000000171001710017017101717
44546ddd06656ddddd556dd0d2226200000000000000000000000000000000000000000000000000000000001710017101710000000171001710017017101700
44546ddd5dd56dddddd56d5d55dd6d56000000000000000000000000000000000000000000000000000000000177771017777771017777710177771001777117
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00222200008f88000000000000000000000000000000000000000000000000000002000000080000000000000000000000000000000000000000000000000000
03b333300b7bbbb00000000000000000000000000000000000000000000000000033300000bbb000000000000000000000000000000000000000000000000000
0535555003b333300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000008888880888088888888888888888888888880808888888888888088888
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000880080000008808880000888000000000008008000000008808000
00000000000000000000000000000000000000000000000000000000000000000000000080888888000088888888000881800880000088888880000088888880
00000000000000000000000000000000000000000000000000000000000000000000000888888888000088811881808881818888000088888818000888888881
00000000000000000000000000000000000000000000000000000000000000000000000888888881000888100881818888818888000888818888100088818810
00000000000000000000000000000000000000000000000000000000000000000000008888811110000888100888818888118888800888108888100888881100
00000000000000000000000000000000000000000000000000000000000000000000008188118888000888108888810888100888810888888811000088888800
00000000000000000000000000000000000000000000000000000000000000000000000888188888008088888888108888100888818881888888000008888880
00000000000000000000000000000000000000000000000000000000000000000000008888188881818888888881008888100888110888118888800881188888
00000000000000000000000000000000000000000000000000000000000000000000008888811888818088888888008888808188818888108888818888888881
00000000000000000000000000000000000000000000000000000000000000000000000888888888108888188888800888888188100888108888818888818888
00000000000000000000000000000000000000000000000000000000000000000000000811888888108888108881810888888888100888888818818888881881
00000000000000000000000000000000000000000000000000000000000000000000000118888811000881000818100088188881000888888881100881888110
00000000000000000000000000000000000000000000000000000000000000000000000001111100000110000111000011111110000111111110000011111000
00000000000000000000000000000000000000000000000000000000000000000000008088888808888888888888888808808888888888880888888888888888
__label__
88888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888
88888eeeeee888eeeeee888eeeeee888eeeeee888eeeeee888777777888eeeeee888eeeeee888888888ff8ff8888228822888222822888888822888888228888
8888ee888ee88ee88eee88ee888ee88ee888ee88ee8e8ee88778887788ee8eeee88ee888ee88888888ff888ff888222222888222822888882282888888222888
888eee8e8ee8eeee8eee8eeeee8ee8eeeee8ee8eee8e8ee8777877778eee8eeee8eeeee8ee88888888ff888ff888282282888222888888228882888888288888
888eee8e8ee8eeee8eee8eee888ee8eeee88ee8eee888ee8777888778eee888ee8eeeee8ee88e8e888ff888ff888222222888888222888228882888822288888
888eee8e8ee8eeee8eee8eee8eeee8eeeee8ee8eeeee8ee8777778778eee8e8ee8eeeee8ee88888888ff888ff888822228888228222888882282888222288888
888eee888ee8eee888ee8eee888ee8eee888ee8eeeee8ee8777888778eee888ee8eeeee8ee888888888ff8ff8888828828888228222888888822888222888888
888eeeeeeee8eeeeeeee8eeeeeeee8eeeeeeee8eeeeeeee8777777778eeeeeeee8eeeeeeee888888888888888888888888888888888888888888888888888888
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
1eee1e1e1ee111ee1eee1eee11ee1ee1111116661111161616661661166616661666117116661171111111111111111111111111111111111111111111111111
1e111e1e1e1e1e1111e111e11e1e1e1e111116161111161616161616161611611611171116161117111111111111111111111111111111111111111111111111
1ee11e1e1e1e1e1111e111e11e1e1e1e111116611111161616661616166611611661171116611117111111111111111111111111111111111111111111111111
1e111e1e1e1e1e1111e111e11e1e1e1e111116161111161616111616161611611611171116161117111111111111111111111111111111111111111111111111
1e1111ee1e1e11ee11e11eee1ee11e1e111116661666116616111666161611611666117116661171111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
111111111111111111dd11dd1d111d111ddd1dd11ddd1ddd11111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111d111d1d1d111d1111d11d1d1d11111d11111111111111111111111111111111111111111111111111111111111111111111111111111111
11111ddd1ddd11111d111d1d1d111d1111d11d1d1dd111dd11111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111d111d1d1d111d1111d11d1d1d11111111111111111111111111111111111111111111111111111111111111111111111111111111111111
111111111111111111dd1dd11ddd1ddd1ddd1ddd1ddd11d111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111eee1eee111116661111116611661611161116661661166611111eee1e1e1eee1ee111111111111111111111111111111111111111111111111111111111
111111e11e111111161611111611161616111611116116161611111111e11e1e1e111e1e11111111111111111111111111111111111111111111111111111111
111111e11ee11111166111111611161616111611116116161661111111e11eee1ee11e1e11111111111111111111111111111111111111111111111111111111
111111e11e111111161611111611161616111611116116161611111111e11e1e1e111e1e11111111111111111111111111111111111111111111111111111111
11111eee1e111111166611711166166116661666166616661666111111e11e1e1eee1e1e11111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111166611111661166611661666166616161661117116661171111111111111111111111111111111111111111111111111111111111111111111111111
11111111161611111616161116111616161616161616171116161117111111111111111111111111111111111111111111111111111111111111111111111111
11111111166111111616166116661666166616161616171116611117111111111111111111111111111111111111111111111111111111111111111111111111
11111111161611111616161111161611161616661616171116161117111111111111111111111111111111111111111111111111111111111111111111111111
11111111166616661666166616611611161616661616117116661171111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111166611111666161616661611116616611666117116661111161611111111166611111616117111111111111111111111111111111111111111111111
11111111161611111611161616161611161616161611171116161111161611111111161611111616111711111111111111111111111111111111111111111111
11111111166111111661116116661611161616161661171116611111116111111111166111111171111711111111111111111111111111111111111111111111
11111111161611111611161616111611161616161611171116161111161611711111161611111177111711111111111111111111111111111111111111111111
11111111166616661666161616111666166116661666117116661171161617111111166611711177717111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111177771111111111111111111111111111111111111111111111
11111eee1ee11ee11111111111111111111111111111111111111111111111111111111111111177111111111111111111111111111111111111111111111111
11111e111e1e1e1e1111111111111111111111111111111111111111111111111111111111111111711111111111111111111111111111111111111111111111
11111ee11e1e1e1e1111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111e111e1e1e1e1111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111eee1e1e1eee1111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
111111111111111111dd1ddd1ddd111111dd1ddd1ddd1ddd1ddd1ddd11111d1d11111dd11ddd1ddd1ddd11dd1ddd1ddd11dd1dd1111111111111111111111111
11111111111111111d111d1111d111111d111d1d1d1d11d111d11d1111111d1d11111d1d11d11d1d1d111d1111d111d11d1d1d1d11d111111111111111111111
11111ddd1ddd11111ddd1dd111d111111ddd1ddd1dd111d111d11dd111111ddd11111d1d11d11dd11dd11d1111d111d11d1d1d1d111111111111111111111111
1111111111111111111d1d1111d11111111d1d111d1d11d111d11d111111111d11111d1d11d11d1d1d111d1111d111d11d1d1d1d11d111111111111111111111
11111111111111111dd11ddd11d111111dd11d111d1d1ddd11d11ddd1111111d11111ddd1ddd1d1d1ddd11dd11d11ddd1dd11d1d111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111eee1eee1111166611111616161611111171111111111ccc11111eee1e1e1eee1ee111111666111116111166116616161111111111111666111116161616
111111e11e111111161611111616161611111171177711111c1c111111e11e1e1e111e1e11111616111116111616161616161111177711111616111116161616
111111e11ee11111166111111616116111111171111111111c1c111111e11eee1ee11e1e11111661111116111616161616611111111111111661111116161161
111111e11e111111161611111666161611111111177711111c1c111111e11e1e1e111e1e11111616111116111616161616161111177711111616111116661616
11111eee1e111111166611711161161611111171111111111ccc111111e11e1e1eee1e1e11111666117116661661166116161111111111111666117111611616
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111eee1eee1111166611111616161611111171111111111ccc111111ee1eee1111166611111616161611111171111111111ccc11111eee1e1e1eee1ee11111
111111e11e111111161611111616161611111171177711111c1c11111e1e1e1e1111161611111616161611111171177711111c1c111111e11e1e1e111e1e1111
111111e11ee11111166111111616116111111171111111111c1c11111e1e1ee11111166111111616166611111171111111111c1c111111e11eee1ee11e1e1111
111111e11e111111161611111666161611111111177711111c1c11111e1e1e1e1111161611111666111611111111177711111c1c111111e11e1e1e111e1e1111
11111eee1e111111166611711161161611111171111111111ccc11111ee11e1e1111166611711161166611111171111111111ccc111111e11e1e1eee1e1e1111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
111111111e1111ee11ee1eee1e11111116161111111111111bbb1bbb11bb11711666111116161616117111111111111111111111111111111111111111111111
111111111e111e1e1e111e1e1e11111116161111177711111b1b1b1b1b1117111616111116161616111711111111111111111111111111111111111111111111
111111111e111e1e1e111eee1e11111111611111111111111bbb1bb11bbb17111661111116161161111711111111111111111111111111111111111111111111
111111111e111e1e1e111e1e1e11111116161111177711111b1b1b1b111b17111616111116661616111711111111111111111111111111111111111111111111
111111111eee1ee111ee1e1e1eee111116161111111111111b1b1bbb1bb111711666117111611616117111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
111111111e1111ee11ee1eee1e1111111666111111111111117111711bbb1bbb1bbb1bb11bbb1171161611111666111116161616117117171ccc11111ccc1111
111111111e111e1e1e111e1e1e1111111616111117771111171117111b1b11b11b1b1b1b111b1711161611111616111116161616111711711c1c11711c1c1111
111111111e111e1e1e111eee1e1111111666111111111111171117111bbb11b11bbb1b1b1bbb1711116111111661111116161666111717771ccc17771c1c1111
111111111e111e1e1e111e1e1e1111111616111117771111171117111b1b11b11b1b1b1b1b111711161611711616111116661116111711711c1c11711c1c1111
111111111eee1ee111ee1e1e1eee11111616111111111111117111711b1b11b11b1b1b1b1bbb1171161617111666117111611666117117171ccc11111ccc11c1
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
111111111666111111661666166611111666111116611666166616661166166616661771166611111cc1117711111cc11c111111111111111111111111111111
1111111116161111161116161616177716161111161611611616111616111616161617111616117111c11117117111c11c111111111111111111111111111111
1111111116611111166616661661111116611111161611611661166616661666166117111666177711c11117177711c11ccc1111111111111111111111111111
1111111116161111111616111616177716161111161611611616161111161611161617111616117111c11117117111c11c1c1111111111111111111111111111
111111111666117116611611161611111666166616661666161616661661161116161771161611111ccc117711111ccc1ccc1111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111eee1ee11ee11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111e111e1e1e1e1111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111ee11e1e1e1e1111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111e111e1e1e1e1111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111eee1e1e1eee1111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
1eee1ee11ee111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
1e111e1e1e1e11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
1ee11e1e1e1e11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
1e111e1e1e1e11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
1eee1e1e1eee11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
1eee1e1e1ee111ee1eee1eee11ee1ee1111116661111166116661166166616661616166111711666117111111111111111111111111111111111111111111111
1e111e1e1e1e1e1111e111e11e1e1e1e111116161111161616111611161616161616161617111616111711111111111111111111111111111111111111111111
1ee11e1e1e1e1e1111e111e11e1e1e1e111116611111161616611666166616661616161617111661111711111111111111111111111111111111111111111111
1e111e1e1e1e1e1111e111e11e1e1e1e111116161111161616111116161116161666161617111616111711111111111111111111111111111111111111111111
88888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888
82888222822882228888822882228882822282228888888888888888888888888888888888888888888882228228822282888882822282288222822288866688
82888828828282888888882882828828888282828888888888888888888888888888888888888888888888828828888282888828828288288282888288888888
82888828828282288888882882228828888282228888888888888888888888888888888888888888888888228828822282228828822288288222822288822288
82888828828282888888882882828828888288828888888888888888888888888888888888888888888888828828828882828828828288288882828888888888
82228222828282228888822282228288888288828888888888888888888888888888888888888888888882228222822282228288822282228882822288822288
88888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888

__map__
0000000000000000000000000000000001000000000000000001004444002800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000004444000000000000444444414040424444000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000028000000000000000000004051000000000000524040404d40404040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000044000000000000000028004000002800000000004040404040404040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000004140000000000000000043444044444300000100285452404040404051000000000000010000000100000001000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000414040000100000000004140404040404042444444444440404e4f405100000000000000000028000000280000002800000100280000000028000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
004440404044440000000000404d404040404040404040404040405e5f400000000000004040404040404040404040404040404040404040404040404040404000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4140404d40404042000000004040404040404040404040404040404040510000000000404040404040404040404040404040404040404040404040404040404000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040000000005452404040405100005300540000526060600000000000000000400000400040004040400040404040404040004040404040404000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404051005300000000000000404040400000000000000000615050500000000000000040404040400040000000000000404040404040004040404040404000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404000000000000000010000524040400000000000000000646564650000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404000000000004444444344444040606373630028000001000028000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404042000000004040404040404040705050507263636363636373630000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
404040404000280041404040404e4f4040705050505050505050505050507200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404d4040404040404040405e5f4040605050505050505050505050505000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
5240404040404040404040404040404070505050505050505050505050505072000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000001000000000000000001004444000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000004444000000000000444444414040424444000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000004051000000000000524040404d40404040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000044000000000000000000004000000000000000004040404040404040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000004140000000000000000043444044444300000100005452404040404051000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000414040000100000000004140404040404042444444444440404e4f405100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
004440404044440000000000404d404040404040404040404040405e5f400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4140404d40404042000000004040404040404040404040404040404040510000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040000000005452404040405100005300540000526060600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404051005300000000000000404040400000000000000000615050500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404000000000000000010000524040400000000000000000646564650000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404000000000004444444344444040606373630000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404042000000004040404040404040705050507263636363636373630000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
404040404000000041404040404e4f4040705050505050505050505050507200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404d4040404040404040405e5f4040605050505050505050505050505000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
5240404040404040404040404040404070505050505050505050505050505072000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
