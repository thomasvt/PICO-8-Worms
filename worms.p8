pico-8 cartridge // http://www.pico-8.com
version 41
__lua__
-- main : m

frame = 0
sprite_shift = 0 -- w_walk_ctrl()

function m_newobj(x,y,vx,vy,spr,r)
 return {
  r=r, -- body radius
	 x=x,y=y, -- pos
	 vx=vx,vy=vy, -- velocity
	 dx=0,dy=0, -- delta p accum
	 thrst=0, -- horiz thrust
	 look=1, -- right or left?
	 spr=spr,
	 grnd=false -- on ground?
	 }
end

function dist(x0,y0,x1,y1)
 local dx = x1-x0
 local dy = y1-y0
 return sqrt(dx*dx+dy*dy)
end

function _init()
	l_gen()

 w_p = m_newobj(40,20,0,0,1,4)	
	add(worms, w_p)
 add(bodies, w_p)
end

function _update()
 w_player_ctrl() 
 foreach(worms, w_update)
 foreach(bodies, p_integrate)
 foreach(bullets, b_update)
 r_update() // particles

 c_update() -- camera
 
 frame+=1
 if frame==1024 then frame = 0 end

end

function _draw()
	cls(0)
 l_draw() -- level
	foreach(bodies, p_draw)
 r_draw() -- particles
	u_draw() -- ui
 print(stat(1))	
 print(debug)
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
function l_gen()
 memset(0x8000,0,stride * lvl_h)

 -- copy map to mem
 for ty = 0,grd_h-1 do
 	for tx = 0,grd_w-1 do
 	
 	 local offs_x = tx<<2
 	 local offs_y = ty<<3
 	 
 		local t = mget(tx,ty)
 		
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

function l_obstacle(x,y)
 x \= 1
 y \= 1
 if x<0 or x>=lvl_w or y<0 or y>=lvl_h then
  return false
 end
 return peek(0x8000+(y<<7)+(x>>1)) > 0
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
  
 local addr = 0x8000+(y0<<7)+(x0>>1)
 for i=y0,y1 do
  memset(addr,0,(x1-x0+2)/2)
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
aim = 0 -- angle
charge = 0 -- max 49

function w_player_ctrl()
 -- toggle mode
 w_shooting = btn(🅾️)

 if w_shooting then
  w_shoot_ctrl()  
 else
  w_walk_ctrl()
 end
end

-- player ctrl in walk mode
function w_walk_ctrl()
 -- toggle zoom
	if btnp(❎) then
	 c_toggle_zoom()
	end
 
 -- jump?
 if w_p.grnd and btnp(⬆️) then 
  w_p.vy = -2 
  w_p.vx = w_p.look*1.5
  w_p.grnd = false
 end
 
 -- walk?
 w_p.thrst = 0
 if w_p.vy == 0 and (btn(➡️) or btn(⬅️)) then
  w_p.thrst = 0.3 -- walk speed
  if btn(⬅️) then w_p.thrst *= -1 end
 end
end

-- player ctrl in shoot mode
function w_shoot_ctrl()
 -- change aim?
 if btn(⬆️) then aim=min(0.25,aim+0.025) end
 if btn(⬇️) then aim=max(-0.25,aim-0.025) end
 
 -- shoot/charge?
 if btn(❎) and charge > -1 and charge<49 then
  charge = min(49, charge+1)
 elseif charge > 0 then
  charge*=0.15 // abuse this var
  b_fire(w_p.x, w_p.y, 
   cos(aim) * charge * w_p.look,
   sin(aim) * charge)
  charge = -1 -- disable successive charging
 end
 if not btn(❎) then
  charge = 0
 end
 
 -- toggle look side?
 if btn(➡️) then
  w_p.thrst = 0.001
 elseif btn(⬅️) then 
  w_p.thrst = -0.001
 end
end

function w_update(w)	

 -- look-direction
 if w.thrst > 0 then
  w.look = 1
 end
 if w.thrst < 0 then
  w.look = -1
 end

 -- which sprite?
 
 if abs(w.thrst) > 0.1 then
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
-->8
-- camera : c
cam_x=0
cam_y=0
cam_x_int=0
c_zoom = 1
c_zoomed = false

c_chase = false

function c_update()
 -- follow target
 local target = w_p.x-64
 local dist = abs(target-cam_x_int) 
 
 if c_chase or (w_p.thrst == 0 and w_p.grnd) then
  if target > cam_x_int then
   cam_x_int += min(3,dist)
  else
   cam_x_int -= min(3,dist)
  end
  if dist < 2 then
   c_chase = false
  end
 else
  if dist > 30 then
   c_chase = true
  end
 end
 
 cam_y = w_p.y-64

 -- round to even (for pixel memory)
	cam_x = cam_x_int \ 2 * 2
end

function c_toggle_zoom()
 c_zoomed = not c_zoomed
	c_zoom = c_zoomed and 2 or 1
	sprite_shift = c_zoomed and 8 or 0	 
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

 if b.y >= 200 then b.collide = true end

 -- on ground?
 b.grnd = l_obstacle(b.x, b.y+b.r+1)

 -- push out of ground (horiz slope)
	while l_obstacle(b.x, b.y+b.r) 
	   or l_obstacle(b.x, b.y+b.r-1) do
	 b.y -= 1
	end
	
	-- gravity
 if b.grnd then
  b.vx /= 2 	
 else
  b.vy += 0.15
	end

 -- accumulate distance to move
 b.dx += b.vx + b.thrst
	b.dy += b.vy
		
	-- ➡️
	while b.dx>=1 do
	 if l_obstacle(b.x+1, b.y) then
    b.dx = 0
 	  b.vx = 0
 	  b.collide = true
		 else 
		  b.x += 1
		  b.dx -= 1
		 end
	end
	
	-- ⬅️
	while b.dx<=-1 do
	 if l_obstacle(b.x-1, b.y) then
    b.dx = 0
 	  b.vx = 0
 	  b.collide = true
		 else 
		  b.x -= 1
		  b.dx += 1
		 end
	end
	
	-- ⬇️
	while b.dy>=1 do
	 if l_obstacle(b.x, b.y+b.r+1) then
    b.dy = 0
 	  b.vy = 0
 	  b.vx = 0
 	  b.collide = true
		 else 
		  b.y += 1
		  b.dy -= 1
		 end
	end
	
	-- ⬆️
	while b.dy<=-1 do
	 if l_obstacle(b.x, b.y-b.r) then
    b.dy = 0
 	  b.vy = 0
 	  b.vx /= 2
 	  b.collide = true
		 else 
		  b.y -= 1
		  b.dy += 1
		 end
	end
end

function p_draw(b)
  local v = c_wrld_to_scr(b)
  spr(b.spr+sprite_shift,
   v.x-3, v.y-3,
   1,1,
   b.look<0,
   false
   )
end
-->8
-- bullets b

b_dir2spr = {0,1,2,1,0,3,4,3}

bullets = {}

	
function b_fire(x,y,vx,vy)
 local b = m_newobj(x,y,vx,vy,16,2)
	add(bodies, b)
	add(bullets, b)
end
	
function b_update(b)
	-- collide?
	if b.collide then
  del(bodies,b)
  del(bullets,b)
  b_explode(b.x+b.vx*2,
   b.y+b.vy*2)
	end

 -- set sprite 4 direction:
 if b.vx != 0 then b.look = b.vx end
 
 if b.vx != 0 or b.vy != 0 then
	 local x = abs(b.vx)
	 local a = ((atan2(x,b.vy)*8+0.5)\1)%8 
		b.spr=b_dir2spr[a+1]+16	 		
	end
end

function b_explode(x,y)
 local r = 10
 local hr = r/2
 local throw_r = r*3
 
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
 
 -- big white flash:
 r_emit(x, y,0, r*1.5,-3, 4,9)
 l_destroy(x,y, r)
 
 y += 4 // lower expl. more upwards throwing
 for _,b in pairs(bodies) do
  local d = dist(b.x,b.y, x,y)
  local to_force = 
   1/d // normalize 
   * (throw_r-d)/throw_r // [0..1] distance
   * 5 // force
  if d < throw_r then
   b.vx = (b.x - x) * to_force
   b.vy = (b.y - y) * to_force
  end
 end
end
-->8
-- ui : u

function u_draw() 

 if w_shooting then
  local dir_x = cos(aim)*w_p.look
  local dir_y = sin(aim)
  
  local pnt = c_wrld_to_scr(w_p)
  
  spr(7+sprite_shift, -- crosshair
   pnt.x-3 + dir_x*15, 
   pnt.y-3 + dir_y*15)
   
  -- charge: 
  if charge > 0 then
   for i=2,charge\2,2 do
    circfill(
     pnt.x + dir_x*i,
     pnt.y + dir_y*i,
     (1+i\4)\c_zoom,
     10-i\8)
   end
  end
 end
end
-->8
-- particles : r

parts = {}

function r_emit(x,y,vy,r,vr,l,col)
 add(parts,{
 x=x,y=y, vy=vy,
 r=r, vr=vr,
 l=l, -- lifetime
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
  circfill(p.x, p.y,
   prt.r\c_zoom,
   prt.col)
 end
end
-->8
-- todo

-- explosion throws worms away
-- camera moves to aim-side
-- 2 worm teams + take turns
-- grenade
-- skip turn
-- place dynamite
-- mine
-- poke
-- uzi
-- cluster bomb
-- die sequence
-- die fall past bottom
-- barrel + fire particles
__gfx__
000000000000fff00000000000000000000fff000007f70000000000009990000000000000000000000000000000000000000000000000000000000000000000
00000000000f7f7f000000000000fff000ff7f7000f1f1f00ff00000090909000000000000000000000000000000000000000000000000000000000000090000
00000000000f1f1f00000000000ff7f700ff1f1000f7f7f0fffff0009009009000000000000ff000000000000000ff00000ff000000fd00000ff000000090000
00000000000f7f7f00000000000ff1f100ff7f7000fffff000fffff09997999000000000000dd000000000000000fd00000fd000000ff000000ff00009909900
000000000000ffff00000000000ff7f700fffff000fffff000ff7f7f900900900000000000fff0000000000000ffff0000fff00000fff000000fd00000090000
0000000000fffff0000000000000ffff0fffff00000fff00000f1f1f09090900000000000fff0000000000000f0ff00000ff000000f00000000ff00000090000
000000000ffffff0000000000ffffff0ffffff00000fff00000f7f7f009990000000000000000000000000000000000000000000000000000000000000000000
00000000ff0fff0000000000ff0fff00f0fff00000fff0000000fff0000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000ee00005600000000660000000000000000000000000000000000000ee00000ee000000d00000001100000000000000000000000000000
000000000000ee00008998005110000000611600000000000000000000000000ddde00000d1800000110000011d0000001100000000000000000000000000000
060dddf0000d890000188100511dd000000dd00000000000000000000000000011180000d1100000011000000118000001100000000000000000000000000000
51d1189800d118000011110000d1110000d11d000000000000000000000000000000000001000000011000000022000002200000000000000000000000000000
51111898001111000011110000111880001111000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
050111806d1110000001100000018420001221000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000511000000051150000002200002442000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000055000000005500000000000000220000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
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
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
44544445000000e33000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004454444544544445
55454445000003353300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005545444555454445
4444555500000333433c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004466666546666664
44454544000935434433000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006666666665561566
44544544000335444454400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006dd6666611561d6d
55444545003443455544333000300090003003000000000000000000000000000000000000000000000000000000000000000000000000006d6666661116dddd
4454445403344454445444303003003330303000000000000000000000000000000000000000000000000000000000000000000000000000666666dd66666611
4454445434544454445444533333333333333333000000000000000000000000000000000000000000000000000000000000000000000000d66dd717ddd6d1dd
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007dd715511ddd1ddd
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000057155411111176dd
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000044445551111766d1
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000044454511117666d1
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004454111717666dd5
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000055471716666ddd55
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000044566666dddd5554
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004455dddd15554454
__label__
70000000888800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
07000000888800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700000888800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
07000000888800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
70000000888800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
99999999000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
99999999000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
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
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000bbb000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000bbbbb00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000bbbb0b00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000bbb0bbb0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000bbbb0bb0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000bbbbbb00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
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
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000

__map__
4000000000000000400000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000004344000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000043414040424444430000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000044434140404040404040404200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000004344444140404040404040000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000414040404040000040000000000000004000004400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
44434040404e4f40434443440000434400000000414000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
40400000405e5f40404040400000404042444341400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000040404000000000000000004040404040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
