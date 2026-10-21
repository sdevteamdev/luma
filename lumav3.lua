-- Luma OS 3 alpha installer. Run once from OpenOS.
local component=require("component")
local computer=require("computer")
local fs=require("filesystem")
local function write(path,data)
 local dir=fs.path(path);if not fs.exists(dir) then assert(fs.makeDirectory(dir)) end
 local tmp=path..".new";local f=assert(io.open(tmp,"wb"));assert(f:write(data));assert(f:flush());local _,ce=f:close();assert(not ce,ce)
 if fs.exists(path) then
  if fs.exists(path..".bak") then assert(fs.remove(path..".bak")) end
  assert(fs.rename(path,path..".bak"))
 end
 local ok,err=fs.rename(tmp,path)
 if not ok then if fs.exists(path..".bak") then fs.rename(path..".bak",path) end;error(err or "rename failed") end
end
assert(component.isAvailable("eeprom"),"EEPROM not found")
local e=component.eeprom
local bios=[==[-- LuBIOS 0.3: standalone EEPROM firmware; boots Luma and standard /init.lua.
local C,P=component,computer
local function call(a,m,...)
 local r=table.pack(pcall(C.invoke,a,m,...));if r[1] then return table.unpack(r,2,r.n) end
 return nil,r[2]
end
local ee=C.list('eeprom')()
P.getBootAddress=function() return call(ee,'getData') end
P.setBootAddress=function(a) return call(ee,'setData',a or '') end
local g,s=C.list('gpu')(),C.list('screen')()
local w,h,depth=40,16,1
if g and s then
 call(g,'bind',s)
 local x,y=call(g,'maxResolution');w,h=math.min(x or 40,80),math.min(y or 16,25)
 call(g,'setResolution',w,h)
 local d=call(g,'maxDepth');if d then depth=d;call(g,'setDepth',d) end
 if depth>1 then for i,c in ipairs({0x0D131E,0x172231,0x8EDBD3,0xE5ECF6,0x8195AE,0xF4A99C}) do call(g,'setPaletteColor',i-1,c) end end
end
local function text(y,t,c)
 if not(g and s) or y<1 or y>h then return end
 call(g,'setForeground',depth==1 and 0xFFFFFF or c or 0xE5ECF6)
 local n=unicode and unicode.len(t) or #t
 if n>w-4 then t=unicode and unicode.sub(t,1,w-4) or t:sub(1,w-4) end
 call(g,'set',3,y,t)
end
local function draw(title,note)
 if not(g and s) then return end
 call(g,'setBackground',depth==1 and 0 or 0x0D131E);call(g,'fill',1,1,w,h,' ')
 call(g,'setBackground',depth==1 and 0 or 0x172231);call(g,'fill',1,1,w,3,' ')
 text(2,'LUMA / LuBIOS 0.3',0x8EDBD3);call(g,'setBackground',depth==1 and 0 or 0x0D131E)
 text(5,title);text(h-2,note or 'F2 Recovery  /  F3 Boot menu',0x8195AE)
end
local function loadfile(fs,path)
 local f,e=call(fs,'open',path,'r');if not f then return nil,e end
 local t,n={},0
 while true do
  local b,er=call(fs,'read',f,4096)
  if not b then call(fs,'close',f);if er then return nil,er end;break end
  n=n+#b;if n>262144 then call(fs,'close',f);return nil,'Boot file exceeds 256 KiB' end
  t[#t+1]=b
 end
 return load(table.concat(t),'='..path,'t',_G)
end
local recovery,menu=false,false
draw('Firmware ready')
text(7,('Memory: %d KiB'):format(math.floor(P.totalMemory()/1024)),0x8EDBD3)
local untilAt=P.uptime()+1
while P.uptime()<untilAt do
 local e={P.pullSignal(math.max(0,untilAt-P.uptime()))}
 if e[1]=='key_down' then recovery=e[4]==60;menu=e[4]==61;if recovery or menu then break end end
end
local disks={};local preferred=P.getBootAddress()
for fs in C.list('filesystem') do
 if fs==preferred then table.insert(disks,1,fs) else disks[#disks+1]=fs end
end
local function choose()
 local i=1
 while true do
  draw('Select boot disk','Arrows: select  Enter: boot  Esc: auto')
  local rows=math.max(1,h-9);local top=math.max(1,i-rows+1)
  for j=top,math.min(#disks,top+rows-1) do
   local label=call(disks[j],'getLabel') or disks[j]:sub(1,8)
   text(6+j-top,(i==j and '> ' or '  ')..tostring(label),i==j and 0x8EDBD3 or 0x8195AE)
  end
  local e={P.pullSignal()}
  if e[1]=='key_down' then
   if e[4]==200 then i=math.max(1,i-1) elseif e[4]==208 then i=math.min(#disks,i+1)
   elseif e[4]==28 then local fs=table.remove(disks,i);table.insert(disks,1,fs);return
   elseif e[4]==1 then return end
  end
 end
end
if menu and #disks>0 then choose() end
local reason='No bootable disk'
for _,fs in ipairs(disks) do
 local f,e
 if recovery then f,e=loadfile(fs,'/boot/luma/recovery.lua') end
 if not f then f,e=loadfile(fs,'/boot/luma/kernel.lua') end
 if not f then f,e=loadfile(fs,'/init.lua') end
 if f then
  P.setBootAddress(fs);LUMA_BOOT_ADDRESS=fs;draw('Starting system...','Boot disk: '..fs:sub(1,8));return f()
 end
 reason=e or reason
end
draw('Unable to boot','Insert a boot disk. Enter: restart')
text(7,tostring(reason),0xF4A99C)
while true do local e={P.pullSignal()};if e[1]=='key_down' and e[4]==28 then P.shutdown(true) end end
]==]
assert(#bios<=e.getSize(),"LuBIOS does not fit this EEPROM")
assert(load(bios,"=LuBIOS","t"))
local old,oldData,oldLabel=e.get() or "",e.getData() or "",e.getLabel() or ""
if not fs.exists("/boot/luma/eeprom-backup.lua") then
 write("/boot/luma/eeprom-backup.lua",old)
 write("/boot/luma/eeprom-backup.data",oldData)
 write("/boot/luma/eeprom-backup.label",oldLabel)
end
write('/boot/luma/kernel.lua',[==[-- LuKernel 0.2 alpha. Bare-metal Luma OS kernel; does not require OpenOS.
local C,PC=component,computer
local boot=LUMA_BOOT_ADDRESS or (PC.getBootAddress and PC.getBootAddress())
local function invoke(a,m,...) local r=table.pack(pcall(C.invoke,a,m,...));if not r[1] then return nil,r[2] end;return table.unpack(r,2,r.n) end
local function first(t) return C.list(t)() end
local gpu,screen=first('gpu'),first('screen')
if not gpu or not screen then error('LuKernel: GPU and screen required',0) end
assert(invoke(gpu,'bind',screen))
local depth=invoke(gpu,'getDepth') or 1
local maxDepth=invoke(gpu,'maxDepth') or depth
if depth<4 then for _,d in ipairs({8,4,1}) do if d<=maxDepth and invoke(gpu,'setDepth',d) then depth=d;break end end end
local mw,mh=invoke(gpu,'maxResolution');mw,mh=tonumber(mw) or 80,tonumber(mh) or 25
local w,h=math.min(mw,120),math.min(mh,40)
assert(w>=50 and h>=16,'LuKernel: minimum screen is 50x16')
local resized,resizeError=invoke(gpu,'setResolution',w,h)
assert(resized~=nil,resizeError or 'LuKernel: screen resize failed')
local P={bg=0x0D131E,panel=0x172231,line=0x294654,text=0xE5ECF6,muted=0x8195AE,accent=0x8EDBD3,warn=0xF3CD78,danger=0xF4A99C}
if depth==1 then for k in pairs(P) do P[k]=(k=='bg' or k=='panel' or k=='line') and 0 or 0xFFFFFF end end
-- Install the shared UI/video palette. OC's fixed RGB cube otherwise turns
-- the dark blue theme into grey even on a tier-3 screen.
local palette={0x0D131E,0x172231,0x294654,0x428995,0x8EDBD3,0xE5ECF6,0x4D80CD,0x8ABAF0,0x66B09F,0xB6E8D8,0x9D88C5,0xD0C5E8,0xC28E3F,0xF3CD78,0x8195AE,0xF4A99C}
if depth>1 then for i,c in ipairs(palette) do invoke(gpu,'setPaletteColor',i-1,c) end end
local function color(f,b) invoke(gpu,'setForeground',f);invoke(gpu,'setBackground',b or P.bg) end
local function fill(x,y,ww,hh,b) color(P.text,b);invoke(gpu,'fill',x,y,ww,hh,' ') end
local function text(x,y,s,f,b,max) s=tostring(s or '');if max and unicode and unicode.len(s)>max then s=unicode.sub(s,1,max-1)..'…' end;color(f or P.text,b or P.bg);invoke(gpu,'set',x,y,s) end
local function center(y,s,f,b) local n=unicode and unicode.len(s) or #s;text(math.max(1,math.floor((w-n)/2)+1),y,s,f,b) end
local function fsOpen(path,mode) return invoke(boot,'open',path,mode or 'r') end
local function fsRead(path,limit) local hnd,e=fsOpen(path);if not hnd then return nil,e end;local t,n={},0;while true do local s,er=invoke(boot,'read',hnd,8192);if not s then invoke(boot,'close',hnd);if er then return nil,er end;break end;n=n+#s;if limit and n>limit then invoke(boot,'close',hnd);return nil,'file too large' end;t[#t+1]=s end;return table.concat(t) end
local function fsList(path) local it,e=invoke(boot,'list',path);if not it then return {},e end;local t={};if type(it)=='table' then for _,v in ipairs(it) do t[#t+1]=v end else while true do local v=it();if not v then break end;t[#t+1]=v end end;table.sort(t);return t end
local function fsWrite(path,data)
 local hnd,e=fsOpen(path,'w');if not hnd then return nil,e end
 local ok,er=invoke(boot,'write',hnd,data);local closed,ce=invoke(boot,'close',hnd)
 if not ok then return nil,er end;if ce then return nil,ce end;return true
end
local function loadLib(path)
 local src,e=fsRead(path,65536);if not src then return nil,e end
 local fn,le=load(src,'='..path,'t',_G);if not fn then return nil,le end
 local ok,r=pcall(fn);if not ok then return nil,r end;return r
end
local accel=first('luma_accelerator');local accelTier,accelBudget=0,1
if accel then local a,b=invoke(accel,'info');accelTier=tonumber(a) or 0;accelBudget=tonumber(b) or 1 end
local function memoryText()
 local free,total=PC.freeMemory(),PC.totalMemory()
 if total>=1024*1024 then return ('RAM %d/%dM'):format(math.floor(free/1048576),math.floor(total/1048576)) end
 return ('RAM %d/%dK'):format(math.floor(free/1024),math.floor(total/1024))
end
local function lumaRamKiB()
 local total=0
 for address in C.list('luma_memory') do local n=invoke(address,'capacity');total=total+(tonumber(n) or 0) end
 return total
end
local config={eco=true,accent='mint'}
local cfg=fsRead('/system/luma/settings.cfg',4096)
if cfg then for k,v in cfg:gmatch('([%a_]+)=([^\n]+)') do if k=='eco' then config.eco=v=='1' elseif k=='accent' then config.accent=v end end end
local page='home';local index=1;local message='';local messageUntil=0;local lastClock=-1;local running=true
local menu={{'Медиатека','media'},{'Файлы','files'},{'Приложения','apps'},{'Диагностика','diag'},{'Настройки','settings'}}

-- Horizon is optional at boot: direct rendering remains as the recovery path.
local Compositor=loadLib('/system/luma/lib/compositor.lua')
local Horizon=loadLib('/system/luma/lib/horizon.lua')
local LuVid=loadLib('/system/luma/lib/luvid.lua')
if depth==1 then
 if Horizon then for k in pairs(Horizon.theme) do Horizon.theme[k]=(k=='bg' or k=='panel' or k=='active') and 0 or 0xFFFFFF end end
 if LuVid then for i,c in ipairs(LuVid.palette) do
  local r,g,b=math.floor(c/65536)%256,math.floor(c/256)%256,c%256
  LuVid.palette[i]=(r*299+g*587+b*114>=128000) and 0xFFFFFF or 0
 end end
end
local Audio=loadLib('/system/luma/lib/audio.lua')
local VFS=loadLib('/system/luma/lib/vfs.lua')
local LuPackage=loadLib('/system/luma/lib/lupackage.lua')
local vfs
if VFS then local ok,result=pcall(VFS.new,C,boot,invoke);if ok then vfs=result end end
local comp,homeNodes,homeButtons,homeFocus,footerLabel
local systemNodes,systemButtons,systemFocus,systemFooter={},{},nil,nil
local filePath='/'
local listPages={files=0,media=0,apps=0};local listPageCount=1
local function header(title)
 fill(1,1,w,h,P.bg);fill(1,1,w,3,P.panel);text(3,2,'LUMA OS 3.0α',P.accent,P.panel);text(math.max(24,w-30),2,title or 'Главная',P.text,P.panel)
 fill(1,h-1,w,2,P.panel);text(2,h-1,message~='' and message or 'Стрелки: выбор · Enter: открыть · F1: домой',message~='' and P.accent or P.muted,P.panel,w-2)
 local hw=accelTier>0 and ('LumaChip L'..accelTier..' ×'..accelBudget) or 'STOCK';text(math.max(1,w-#hw-1),h,hw,accelTier>0 and P.accent or P.warn,P.panel)
end
local function button(y,label,selected)
 local b=selected and P.line or P.panel;fill(4,y,w-8,3,b);if selected then fill(4,y,1,3,P.accent) end;text(7,y+1,label,selected and P.accent or P.text,b,w-12)
end
local function hideHome() if homeNodes then for _,n in ipairs(homeNodes) do n.visible=false end end end
local function openPage(target) page=target;index=1;hideHome() end
local function buildHome()
 if not (Compositor and Horizon and C.proxy) then return false end
 local ok,gp=pcall(C.proxy,gpu);if not ok or not gp then return false end
 comp=Compositor.new(gp,w,h,Horizon.theme);homeNodes={};homeButtons={};homeFocus=Horizon.focus(comp)
 local function keep(n) homeNodes[#homeNodes+1]=n;return n end
 keep(Horizon.panel(comp,1,1,w,1,0,P.panel))
 keep(Horizon.label(comp,3,1,18,'LUMA',P.accent,P.panel,2))
 keep(Horizon.label(comp,math.max(24,math.floor(w/2)-3),1,12,'Главная',P.text,P.panel,2))
 local hw=accelTier>0 and ('LumaChip L'..accelTier) or 'STOCK'
 keep(Horizon.label(comp,math.max(2,w-#hw-1),1,#hw,hw,accelTier>0 and P.accent or P.warn,P.panel,2))
 keep(Horizon.label(comp,3,3,w-6,'Система работает без OpenOS',P.muted,P.bg,2))
 keep(Horizon.label(comp,3,4,w-6,accelTier>0 and 'Аппаратное ускорение активно' or 'Совместимый режим штатного оборудования',accelTier>0 and P.accent or P.warn,P.bg,2))
 local cols=w>=100 and 2 or 1;local gap=2;local bx=3;local bw=cols==2 and math.floor((w-bx*2-gap)/2) or w-bx*2
 local by=6;local step=h<22 and 1 or h<=25 and 3 or 4;local bh=h<22 and 1 or 3
 for i,m in ipairs(menu) do
  local col=(i-1)%cols;local row=math.floor((i-1)/cols)
  local target=m[2]
  local n=keep(Horizon.button(comp,bx+col*(bw+gap),by+row*step,bw,bh,m[1],function() openPage(target) end,3))
  homeButtons[#homeButtons+1]=n;homeFocus:add(n)
 end
 keep(Horizon.panel(comp,1,h,w,1,0,P.panel))
 footerLabel=keep(Horizon.label(comp,2,h,math.max(1,w-26),'Стрелки · Enter · F1',P.muted,P.panel,2))
 keep(Horizon.label(comp,math.max(2,w-22),h,20,memoryText(),P.accent,P.panel,2))
 return true
end
local horizonReady=buildHome()
local function showHome(full)
 page='home';if not horizonReady then return false end
 for _,n in ipairs(homeNodes) do n.visible=true end
 footerLabel.text=message~='' and message or 'Стрелки · Enter · F1'
 if full then comp:invalidateAll() end
 comp:flush();return true
end
local function drawHome() if not showHome(true) then header('Главная');local y=6;for i,m in ipairs(menu) do button(y+(i-1)*3,m[1],i==index) end end end
local function clearSystem()
 if not comp then return end
 for _,n in ipairs(systemNodes) do comp:remove(n) end
 systemNodes={};systemButtons={};systemFocus=nil;systemFooter=nil
end
local buildSystem
local function mediaFiles()
 local out={}
 local function scan(dir)
  local list=fsList(dir)
  for _,name in ipairs(list) do if name:lower():match('%.lvd$') then out[#out+1]={name=name,path=(dir=='/' and '/' or dir..'/')..name} end end
 end
 scan('/media');if #out==0 then scan('/') end
 return out
end
local function playLuVid(path)
 if not LuVid then message='Media Core повреждён или не установлен';messageUntil=PC.uptime()+4;return end
 local hnd,e=fsOpen(path,'r');if not hnd then message='Не открыть '..path..': '..tostring(e);messageUntil=PC.uptime()+4;return end
 local reader={}
 function reader:read(n) return invoke(boot,'read',hnd,n) end
 function reader:seek(whence,n) return invoke(boot,'seek',hnd,whence,n) end
 function reader:close() local ok,er=invoke(boot,'close',hnd);hnd=nil;return ok,er end
 local decoder=accel and {decodeRLE=function(data,n) return invoke(accel,'decodeRLE',data,n) end} or nil
 local video,er=LuVid.open(reader,decoder)
 if not video then reader:close();message='LuVid: '..tostring(er);messageUntil=PC.uptime()+4;return end
 clearSystem();fill(1,1,w,h,P.bg)
 local tape=first('tape_drive');local audioCard=first('audio');local audioStream;local audioReady=false;local audioLabel=video.audioBytes>0 and 'звук отключён' or 'без аудио'
 if video.audioBytes>0 and audioCard and Audio then
  text(2,2,'Подготовка потокового DFPWM audio…',P.accent,P.bg,w-2)
  local at,ae=video:scanAudio()
  if at then
   local ah,err=fsOpen(path,'r')
   if ah then
    invoke(boot,'seek',ah,'set',at)
    local ar={read=function(_,n) return invoke(boot,'read',ah,n) end,close=function() if ah then invoke(boot,'close',ah);ah=nil end end}
    audioStream=Audio.new(invoke,audioCard,ar,video.audioBytes,PC.uptime)
    local ready,why=pcall(function() audioStream:start() end)
    if ready then audioLabel='DFPWM · OC Audio · поток 32 KiB' else audioStream:close();audioStream=nil;audioLabel='аудио: '..tostring(why) end
   else audioLabel='аудио: '..tostring(err) end
   video:rewind()
  else audioLabel='аудио: '..tostring(ae) end
 elseif video.audioBytes>0 and tape then
  local ready=invoke(tape,'isReady');local capacity=ready and tonumber(invoke(tape,'getSize')) or 0
  if not ready then audioLabel='вставьте кассету'
  elseif video.audioBytes>capacity then audioLabel='аудио длиннее кассеты'
  else
   text(2,2,'Подготовка DFPWM audio…',P.accent,P.bg,w-2)
   local audioAt,ae=video:scanAudio()
   if audioAt then
    invoke(tape,'stop');local pos=tonumber(invoke(tape,'getPosition')) or 0;invoke(tape,'seek',-pos)
    reader:seek('set',audioAt);local left=video.audioBytes;local loaded=0
    while left>0 do
     local chunk,re=reader:read(math.min(8192,left));if not chunk or #chunk==0 then ae=re or 'аудио обрезано';break end
     local wrote,we=invoke(tape,'write',chunk);if wrote==nil and we then ae=we;break end
     left=left-#chunk;loaded=loaded+#chunk
     if loaded%65536<8192 then text(2,3,('%d%%'):format(math.floor(loaded*100/video.audioBytes)),P.muted,P.bg,8) end
    end
    video:rewind();pos=tonumber(invoke(tape,'getPosition')) or 0;invoke(tape,'seek',-pos)
    if left==0 then audioReady=true;audioLabel='DFPWM tape audio clock' else audioLabel='ошибка аудио: '..tostring(ae) end
   else audioLabel='ошибка аудио: '..tostring(ae) end
  end
 end
 local paused,stop=false,false;local nextAt=PC.uptime();local lastFrame;local dropped=0
 local ok,why=pcall(function()
  if audioReady then invoke(tape,'setSpeed',1);invoke(tape,'play') end
  while not stop do
   local now=PC.uptime()
   if audioStream and not paused then
    if not audioStream:pump() then audioStream:close();audioStream=nil;audioLabel='DFPWM завершён';nextAt=now end
   end
   if not paused and now>=nextAt then
    local desired
    if audioStream then
     desired=math.min(video.count,math.floor(audioStream:position()*video.fps)+1);nextAt=now+.02
    elseif audioReady then
     local apos=tonumber(invoke(tape,'getPosition')) or 0;desired=math.min(video.count,math.floor(apos/6000*video.fps)+1);nextAt=now+.02
     if apos>=video.audioBytes then audioReady=false;audioLabel='DFPWM завершён';desired=math.min(video.count,video.index+1);nextAt=now+1/video.fps end
    else
     desired=math.min(video.count,video.index+1+math.max(0,math.floor((now-nextAt)*video.fps)));nextAt=nextAt+(desired-video.index)/video.fps
    end
    while video.index+1<desired do local skipped,se=video:skipFrame();if not skipped then error(se,0) end;dropped=dropped+1 end
    if desired>video.index then
     local frame,fe=video:nextFrame();if not frame then if fe=='end' then break else error(fe,0) end end
     lastFrame=frame;fill(1,1,w,h-2,P.bg);LuVid.draw(comp.gpu,frame,video.w,video.h,1,2,w,h-4)
     fill(1,1,w,1,P.panel);text(2,1,('LuVid · %s · %d/%d · %s · drop %d'):format(path,video.index,video.count,video.backend,dropped),P.accent,P.panel,w-2)
     fill(1,h-1,w,2,P.panel);text(2,h-1,'Space: пауза · Esc/F1: медиатека',P.muted,P.panel,w-2)
     text(2,h,audioLabel,(audioReady or audioStream) and P.accent or P.muted,P.panel,w-2)
    elseif video.index>=video.count and not audioStream and not audioReady then break end
   end
   local timeout=paused and .25 or math.max(0,math.min(.1,nextAt-PC.uptime()))
   local ev={PC.pullSignal(timeout)}
   if ev[1]=='key_down' then
    local key=ev[4]
    if key==1 or key==59 then stop=true
    elseif key==57 then
     paused=not paused
     if audioStream then audioStream:setPaused(paused) end
     if audioReady then if paused then invoke(tape,'stop') else invoke(tape,'play') end end
     if not paused then nextAt=PC.uptime()+1/video.fps elseif lastFrame then fill(1,h,w,1,P.panel);text(2,h,'Пауза',P.warn,P.panel,w-2) end
    end
   end
  end
 end)
 if audioStream then audioStream:close() end
 if audioReady then invoke(tape,'stop');local pos=tonumber(invoke(tape,'getPosition')) or 0;invoke(tape,'seek',-pos) end
 video:close()
 message=ok and 'Воспроизведение завершено' or ('Ошибка LuVid: '..tostring(why));messageUntil=PC.uptime()+4
 page='media';buildSystem('media')
end
local function installedApps()
 local out={};if not LuPackage then return out end
 for _,dir in ipairs(fsList('/apps')) do
  local clean=dir:gsub('/$','');local base='/apps/'..clean;local raw=fsRead(base..'/manifest.cfg',8192)
  if raw then local manifest=LuPackage.manifest(raw);if manifest then manifest.base=base;out[#out+1]=manifest end end
 end
 table.sort(out,function(a,b)return a.name:lower()<b.name:lower()end);return out
end
local function runApp(app)
 local source,e=fsRead(app.base..'/'..app.entry,65536);if not source then message='Приложение: '..tostring(e);messageUntil=PC.uptime()+4;return end
 clearSystem()
 local function need(permission) if not app.permissions[permission] then error('нет разрешения '..permission,2) end end
 local api={width=w,height=h,accent=P.accent,muted=P.muted}
 function api.clear() need('screen');fill(1,1,w,h,P.bg) end
 function api.title(s) need('screen');fill(1,1,w,1,P.panel);text(3,1,s,P.accent,P.panel,w-4) end
 function api.center(y,s,c) need('screen');center(y,s,c or P.text,P.bg) end
 function api.text(x,y,s,c) need('screen');text(x,y,s,c or P.text,P.bg,w-x+1) end
 function api.uptime() return PC.uptime() end
 function api.input(timeout) need('input');local e={PC.pullSignal(timeout)};return e[1],e[4],e end
 local runner,le=LuPackage.load(source,'='..app.base..'/'..app.entry,api)
 local ok,why;if runner then ok,why=runner() else ok,why=nil,le end
 message=ok and (app.name..' закрыто') or ('Сбой '..app.name..': '..tostring(why or le));messageUntil=PC.uptime()+5
 page='apps';buildSystem('apps')
end
buildSystem=function(target)
 if not horizonReady then return false end
 clearSystem()
 local function keep(n) systemNodes[#systemNodes+1]=n;return n end
 local titles={diag='Диагностика',files='Файлы',settings='Настройки',media='Медиатека',apps='Приложения'}
 local title=titles[target] or target;listPageCount=1
 keep(Horizon.panel(comp,1,1,w,1,0,P.panel))
 keep(Horizon.label(comp,3,1,18,'LUMA OS 3.0α',P.accent,P.panel,2))
 keep(Horizon.label(comp,math.max(24,w-30),1,28,title,P.text,P.panel,2))
 keep(Horizon.panel(comp,1,h,w,1,0,P.panel))
 systemFooter=keep(Horizon.label(comp,2,h,w-4,message~='' and message or 'Стрелки · Enter · F1: домой',message~='' and P.accent or P.muted,P.panel,2))
 local function listRange(total)
  local a,b,page,pages=Horizon.page(total,h,listPages[target]);listPages[target]=page;listPageCount=pages
  if pages>1 and message=='' then systemFooter.text=('PgUp/PgDn %d/%d · Enter · F1'):format(page+1,pages) end
  return a,b
 end
 if target=='diag' then
  local lr=lumaRamKiB()
  local rows={{'Загрузочный диск',boot},{'GPU depth',depth..' / '..maxDepth},{'Разрешение',w..' × '..h},{'RAM свободно',math.floor(PC.freeMemory()/1024)..' KiB'},{'RAM всего',math.floor(PC.totalMemory()/1024)..' KiB'},{'Luma RAM',lr>0 and (math.floor(lr/1024)..' MiB') or 'не установлена'},{'Ускоритель',accelTier>0 and ('LumaChip L'..accelTier) or 'stock fallback'},{'Call budget',accelBudget},{'Компонентов',0}}
  local count=0;for _ in C.list() do count=count+1 end;rows[#rows][2]=count
  if vfs then local disks=vfs:health();local free=0;for _,d in ipairs(disks) do free=free+d.free end;rows[#rows+1]={'VFS дисков / свободно',#disks..' / '..math.floor(free/1024)..' KiB'} end
  local step=h<22 and 1 or h<30 and 2 or 3
  for i,r in ipairs(rows) do local y=3+(i-1)*step;keep(Horizon.label(comp,4,y,math.floor(w*.42)-5,r[1],P.muted,P.bg,2));keep(Horizon.label(comp,math.floor(w*.42),y,math.floor(w*.55),tostring(r[2]),P.text,P.bg,2)) end
 elseif target=='files' then
  keep(Horizon.label(comp,4,3,w-8,'VFS · '..filePath,P.muted,P.bg,2))
  local list=vfs and (vfs:list(filePath) or {}) or {};systemFocus=Horizon.focus(comp)
  if filePath~='/' then table.insert(list,1,{name='../',path=filePath:match('^(.+)/[^/]+$') or '/',dir=true,parent=true}) end
  if #list==0 then keep(Horizon.label(comp,5,6,w-10,vfs and 'Пусто' or 'VFS не загружен',P.warn,P.bg,2)) end
  local firstRow,lastRow=listRange(#list)
  for i=firstRow,lastRow do
   local item=list[i]
   local suffix=item.dir and '' or (' · '..math.floor((item.size or 0)/1024)..' KiB')
   local n=keep(Horizon.button(comp,4,4+(i-firstRow)*3,w-8,3,item.name..suffix,function()
    if item.dir then filePath=item.path;listPages.files=0;buildSystem('files')
    else message=item.path..' · '..tostring(item.size or 0)..' bytes · Del: в корзину';messageUntil=PC.uptime()+4;systemFooter.text=message;comp:invalidate(systemFooter) end
   end,3));n.vfsItem=item
   systemButtons[#systemButtons+1]=n;systemFocus:add(n)
  end
 elseif target=='media' then
  keep(Horizon.label(comp,4,3,w-8,'LUVID · /media',P.muted,P.bg,2))
  local files=mediaFiles();systemFocus=Horizon.focus(comp)
  if #files==0 then keep(Horizon.label(comp,5,6,w-10,'Файлы .lvd не найдены в /media или /',P.warn,P.bg,2)) end
  local firstRow,lastRow=listRange(#files)
  for i=firstRow,lastRow do
   local item=files[i]
   local n=keep(Horizon.button(comp,4,4+(i-firstRow)*3,w-8,3,item.name,function() playLuVid(item.path) end,3))
   systemButtons[#systemButtons+1]=n;systemFocus:add(n)
  end
 elseif target=='apps' then
  keep(Horizon.label(comp,4,3,w-8,'LUPACKAGE · /apps',P.muted,P.bg,2))
  local apps=installedApps();systemFocus=Horizon.focus(comp)
  if #apps==0 then keep(Horizon.label(comp,5,6,w-10,LuPackage and 'Приложения не установлены' or 'LuPackage runtime не загружен',P.warn,P.bg,2)) end
  local firstRow,lastRow=listRange(#apps)
  for i=firstRow,lastRow do
   local app=apps[i]
   local n=keep(Horizon.button(comp,4,4+(i-firstRow)*3,w-8,3,app.name..' · '..app.version,function() runApp(app) end,3))
   systemButtons[#systemButtons+1]=n;systemFocus:add(n)
  end
 elseif target=='settings' then
  keep(Horizon.label(comp,4,3,w-8,'ПРОИЗВОДИТЕЛЬНОСТЬ И ПИТАНИЕ',P.muted,P.bg,2));systemFocus=Horizon.focus(comp)
  local sy,sgap=h<22 and 4 or 5,h<22 and 3 or 4
  local eco
  eco=keep(Horizon.button(comp,4,sy,w-8,3,'Экономный режим: '..(config.eco and 'включён' or 'выключен'),function(n)
   config.eco=not config.eco;n:setLabel('Экономный режим: '..(config.eco and 'включён' or 'выключен'))
   local ok,e=fsWrite('/system/luma/settings.cfg',('eco=%d\naccent=%s\n'):format(config.eco and 1 or 0,config.accent))
   message=ok and 'Настройки сохранены' or ('Не удалось сохранить: '..tostring(e));messageUntil=PC.uptime()+3;systemFooter.text=message;comp:invalidate(systemFooter)
  end,3))
  local safe=keep(Horizon.button(comp,4,sy+sgap,w-8,3,'Безопасная глубина: '..depth,nil,3));safe.enabled=false
  local reboot=keep(Horizon.button(comp,4,sy+sgap*2,w-8,3,'Перезагрузить компьютер',function() PC.shutdown(true) end,3))
  local shutdown=keep(Horizon.button(comp,4,sy+sgap*3,w-8,3,'Выключить компьютер',function() PC.shutdown(false) end,3))
  for _,n in ipairs({eco,reboot,shutdown}) do systemButtons[#systemButtons+1]=n;systemFocus:add(n) end
 end
 comp:invalidateAll();comp:flush();return true
end
local function drawDiag()
 header('Диагностика');local lr=lumaRamKiB();local rows={{'Загрузочный диск',boot},{'GPU depth',depth..' / reported '..maxDepth},{'Разрешение',w..' × '..h},{'RAM свободно',math.floor(PC.freeMemory()/1024)..' KiB'},{'RAM всего',math.floor(PC.totalMemory()/1024)..' KiB'},{'Luma RAM',lr>0 and (math.floor(lr/1024)..' MiB detected') or 'не установлена'},{'Ускоритель',accelTier>0 and ('LumaChip L'..accelTier) or 'нет — stock fallback'},{'Call budget',accelBudget},{'Компонентов',0}}
 local count=0;for _ in C.list() do count=count+1 end;rows[#rows][2]=count
 local step=h<22 and 1 or h<30 and 2 or 3
 for i,r in ipairs(rows) do local y=4+(i-1)*step;text(4,y,r[1],P.muted);text(math.floor(w*.42),y,tostring(r[2]),P.text,nil,math.floor(w*.56)) end
end
local function drawFiles()
 header('Файлы');local list=fsList('/');text(4,5,'Корень загрузочного диска',P.muted);if #list==0 then text(4,8,'Пусто',P.warn) else for i=1,math.min(#list,h-9) do text(5,6+i,(i==index and '> ' or '  ')..list[i],i==index and P.accent or P.text) end end
end
local function drawSettings()
 header('Настройки');text(4,5,'ПРОИЗВОДИТЕЛЬНОСТЬ',P.muted);button(7,'Экономный режим: '..(config.eco and 'включён' or 'выключен'),index==1);button(11,'Безопасная глубина: '..depth,index==2);button(15,'Перезагрузить компьютер',index==3);button(19,'Выключить компьютер',index==4)
end
local function drawPlaceholder(title,body) header(title);center(math.floor(h/2)-1,title,P.accent);center(math.floor(h/2)+1,body,P.muted) end
local function draw()
 if page=='home' then drawHome() elseif buildSystem(page) then return elseif page=='diag' then drawDiag() elseif page=='files' then drawFiles() elseif page=='settings' then drawSettings() elseif page=='media' then drawPlaceholder('Медиатека','LuVid runtime подключается следующим модулем') else drawPlaceholder('Приложения','LuPackage runtime подключается следующим модулем') end
end
local function home() index=1;clearSystem();if not showHome(true) then page='home';draw() end end
local function activate()
 if page=='home' then
  if horizonReady then homeFocus:activate();draw() else openPage(menu[index][2]);draw() end
 elseif horizonReady and systemFocus then systemFocus:activate();comp:flush()
 elseif page=='settings' then
  if index==1 then config.eco=not config.eco;message='Режим изменён для текущей сессии';messageUntil=PC.uptime()+3;draw()
  elseif index==3 then PC.shutdown(true) elseif index==4 then PC.shutdown(false) end
 end
end
local function move(d)
 if page=='home' and horizonReady then homeFocus:move(0,d);comp:flush();return end
 if horizonReady and systemFocus then systemFocus:move(0,d);comp:flush();return end
 local max=page=='home' and #menu or page=='settings' and 4 or page=='files' and math.max(1,#fsList('/')) or 1
 index=((index-1+d)%max)+1;draw()
end
local function mainLoop()
 draw()
 while running do
  local timeout=config.eco and .25 or .05;local e={PC.pullSignal(timeout)};local name=e[1]
  if name=='key_down' then
   local key=e[4]
   if page=='home' and horizonReady and key==203 then homeFocus:move(-1,0);comp:flush()
   elseif page=='home' and horizonReady and key==205 then homeFocus:move(1,0);comp:flush()
   elseif page=='files' and horizonReady and (key==14 or key==203) and filePath~='/' then filePath=filePath:match('^(.+)/[^/]+$') or '/';listPages.files=0;buildSystem('files')
   elseif page=='files' and horizonReady and key==211 and systemFocus and systemFocus.current and systemFocus.current.vfsItem then
    local item=systemFocus.current.vfsItem
    if item.parent then message='Родительскую папку удалить нельзя'
    else local removed,why=vfs:trash(item.path,math.floor(PC.uptime()*1000));message=removed and ('Перемещено в корзину: '..item.name) or ('Не удалено: '..tostring(why)) end
    messageUntil=PC.uptime()+4;buildSystem('files')
   elseif horizonReady and listPages[page] and (key==201 or key==209) then listPages[page]=listPages[page]+(key==201 and -1 or 1);buildSystem(page)
   elseif key==200 then move(-1) elseif key==208 then move(1) elseif key==28 then activate() elseif key==59 then home() elseif key==1 and page~='home' then home() end
  elseif name=='component_added' or name=='component_removed' then
   if e[3]=='filesystem' and VFS then
    local ok,new=pcall(VFS.new,C,boot,invoke)
    if ok then
     vfs=new
     if filePath~='/' and not vfs:stat(filePath) then filePath='/mnt' end
     if page=='files' or page=='diag' then draw() end
    end
   end
  elseif name=='touch' then
   local tx,ty=e[3],e[4]
   if horizonReady then
    local wasHome=page=='home';local buttons=wasHome and homeButtons or systemButtons;local focus=wasHome and homeFocus or systemFocus
    for _,n in ipairs(buttons) do if tx>=n.x and tx<n.x+n.w and ty>=n.y and ty<n.y+n.h then focus:set(n);comp:flush();n:activate();if wasHome then draw() else comp:flush() end;break end end
   elseif page=='home' then local row=math.floor((ty-6)/3)+1;if row>=1 and row<=#menu then index=row;activate() end end
  end
  local tick=math.floor(PC.uptime()/5)
  if tick~=lastClock then lastClock=tick;if message~='' and PC.uptime()>messageUntil then message='';if page=='home' then showHome(true) else draw() end end end
 end
end
local function trace(e) return debug and debug.traceback(tostring(e),2) or tostring(e) end
local ok,crash=xpcall(mainLoop,trace)
if not ok then
 fsWrite('/system/luma/crash.log',('Luma OS crash\nuptime=%.3f\npage=%s\n%s\n'):format(PC.uptime(),tostring(page),tostring(crash)))
 fill(1,1,w,h,P.danger);text(3,2,'LUMA OS · CRASH SCREEN',P.bg,P.danger,w-4)
 text(3,4,'Ошибка сохранена: /system/luma/crash.log',P.bg,P.danger,w-4)
 local row=6
 for line in tostring(crash):gmatch('[^\n]+') do if row>=h-2 then break end;text(3,row,line,P.bg,P.danger,w-4);row=row+1 end
 text(3,h-1,'Enter: перезагрузить · Esc: выключить',P.bg,P.danger,w-4)
 while true do local e={PC.pullSignal()};if e[1]=='key_down' then if e[4]==28 then PC.shutdown(true) elseif e[4]==1 then PC.shutdown(false) end end end
end
]==])
write('/boot/luma/recovery.lua',[==[-- Luma Recovery 0.1. Loaded by LuBIOS when F2 is pressed.
local C,PC=component,computer
local boot=LUMA_BOOT_ADDRESS or (PC.getBootAddress and PC.getBootAddress())
local function invoke(a,m,...) local r=table.pack(pcall(C.invoke,a,m,...));if not r[1] then return nil,r[2] end;return table.unpack(r,2,r.n) end
local function first(t) return C.list(t)() end
local gpu,screen=first('gpu'),first('screen');assert(gpu and screen,'Recovery requires GPU and screen')
invoke(gpu,'bind',screen);local mw,mh=invoke(gpu,'maxResolution');local w,h=math.min(tonumber(mw) or 80,100),math.min(tonumber(mh) or 25,30);invoke(gpu,'setResolution',w,h)
local bg,fg,accent,danger=0x0D131E,0xE5ECF6,0x8EDBD3,0xF4A99C
if invoke(gpu,'getDepth')==1 then bg,fg,accent,danger=0,0xFFFFFF,0xFFFFFF,0xFFFFFF end
local function text(x,y,s,color) invoke(gpu,'setForeground',color or fg);invoke(gpu,'setBackground',bg);invoke(gpu,'set',x,y,(unicode and unicode.sub(tostring(s),1,w-x+1) or tostring(s):sub(1,w-x+1))) end
local function clear() invoke(gpu,'setBackground',bg);invoke(gpu,'fill',1,1,w,h,' ') end
local function exists(path) return invoke(boot,'exists',path) end
local function loadPath(path)
 local hd,e=invoke(boot,'open',path,'r');if not hd then return nil,e end;local out={}
 while true do local s,er=invoke(boot,'read',hd,8192);if not s then invoke(boot,'close',hd);if er then return nil,er end;break end;out[#out+1]=s end
 local fn,le=load(table.concat(out),'='..path,'t',_G);return fn,le
end
local function restore()
 local files={'/boot/luma/kernel.lua','/system/luma/kernel.lua','/system/luma/lib/compositor.lua','/system/luma/lib/horizon.lua','/system/luma/lib/luvid.lua','/system/luma/lib/audio.lua','/system/luma/lib/vfs.lua','/system/luma/lib/lupackage.lua'}
 local n=0
 for _,path in ipairs(files) do local bak=path..'.bak';if exists(bak) then invoke(boot,'remove',path..'.failed');if exists(path) then invoke(boot,'rename',path,path..'.failed') end;if invoke(boot,'rename',bak,path) then n=n+1 end end end
 return n
end
while true do
 clear();text(3,2,'LUMA RECOVERY',accent);text(3,4,'1 · Продолжить загрузку');text(3,6,'2 · Откатить системные файлы .bak');text(3,8,'3 · Сбросить настройки');text(3,10,'4 · Запустить /init.lua (OpenOS)');text(3,12,'Enter · Перезагрузка');text(3,14,'Esc · Выключение',danger)
 local e={PC.pullSignal()};if e[1]=='key_down' then local key=e[4]
  if key==2 then local fn,er=loadPath('/boot/luma/kernel.lua');if fn then return fn() else text(3,h-2,er,danger);PC.pullSignal(2) end
  elseif key==3 then local n=restore();text(3,h-2,'Восстановлено файлов: '..n,accent);PC.pullSignal(1);PC.shutdown(true)
  elseif key==4 then invoke(boot,'remove','/system/luma/settings.cfg');text(3,h-2,'Настройки сброшены',accent);PC.pullSignal(1)
  elseif key==5 then local fn,er=loadPath('/init.lua');if fn then return fn() else text(3,h-2,er,danger);PC.pullSignal(2) end
  elseif key==28 then PC.shutdown(true) elseif key==1 then PC.shutdown(false) end
 end
end]==])
write('/system/luma/kernel.lua',[==[-- LuKernel 0.2 alpha. Bare-metal Luma OS kernel; does not require OpenOS.
local C,PC=component,computer
local boot=LUMA_BOOT_ADDRESS or (PC.getBootAddress and PC.getBootAddress())
local function invoke(a,m,...) local r=table.pack(pcall(C.invoke,a,m,...));if not r[1] then return nil,r[2] end;return table.unpack(r,2,r.n) end
local function first(t) return C.list(t)() end
local gpu,screen=first('gpu'),first('screen')
if not gpu or not screen then error('LuKernel: GPU and screen required',0) end
assert(invoke(gpu,'bind',screen))
local depth=invoke(gpu,'getDepth') or 1
local maxDepth=invoke(gpu,'maxDepth') or depth
if depth<4 then for _,d in ipairs({8,4,1}) do if d<=maxDepth and invoke(gpu,'setDepth',d) then depth=d;break end end end
local mw,mh=invoke(gpu,'maxResolution');mw,mh=tonumber(mw) or 80,tonumber(mh) or 25
local w,h=math.min(mw,120),math.min(mh,40)
assert(w>=50 and h>=16,'LuKernel: minimum screen is 50x16')
local resized,resizeError=invoke(gpu,'setResolution',w,h)
assert(resized~=nil,resizeError or 'LuKernel: screen resize failed')
local P={bg=0x0D131E,panel=0x172231,line=0x294654,text=0xE5ECF6,muted=0x8195AE,accent=0x8EDBD3,warn=0xF3CD78,danger=0xF4A99C}
if depth==1 then for k in pairs(P) do P[k]=(k=='bg' or k=='panel' or k=='line') and 0 or 0xFFFFFF end end
-- Install the shared UI/video palette. OC's fixed RGB cube otherwise turns
-- the dark blue theme into grey even on a tier-3 screen.
local palette={0x0D131E,0x172231,0x294654,0x428995,0x8EDBD3,0xE5ECF6,0x4D80CD,0x8ABAF0,0x66B09F,0xB6E8D8,0x9D88C5,0xD0C5E8,0xC28E3F,0xF3CD78,0x8195AE,0xF4A99C}
if depth>1 then for i,c in ipairs(palette) do invoke(gpu,'setPaletteColor',i-1,c) end end
local function color(f,b) invoke(gpu,'setForeground',f);invoke(gpu,'setBackground',b or P.bg) end
local function fill(x,y,ww,hh,b) color(P.text,b);invoke(gpu,'fill',x,y,ww,hh,' ') end
local function text(x,y,s,f,b,max) s=tostring(s or '');if max and unicode and unicode.len(s)>max then s=unicode.sub(s,1,max-1)..'…' end;color(f or P.text,b or P.bg);invoke(gpu,'set',x,y,s) end
local function center(y,s,f,b) local n=unicode and unicode.len(s) or #s;text(math.max(1,math.floor((w-n)/2)+1),y,s,f,b) end
local function fsOpen(path,mode) return invoke(boot,'open',path,mode or 'r') end
local function fsRead(path,limit) local hnd,e=fsOpen(path);if not hnd then return nil,e end;local t,n={},0;while true do local s,er=invoke(boot,'read',hnd,8192);if not s then invoke(boot,'close',hnd);if er then return nil,er end;break end;n=n+#s;if limit and n>limit then invoke(boot,'close',hnd);return nil,'file too large' end;t[#t+1]=s end;return table.concat(t) end
local function fsList(path) local it,e=invoke(boot,'list',path);if not it then return {},e end;local t={};if type(it)=='table' then for _,v in ipairs(it) do t[#t+1]=v end else while true do local v=it();if not v then break end;t[#t+1]=v end end;table.sort(t);return t end
local function fsWrite(path,data)
 local hnd,e=fsOpen(path,'w');if not hnd then return nil,e end
 local ok,er=invoke(boot,'write',hnd,data);local closed,ce=invoke(boot,'close',hnd)
 if not ok then return nil,er end;if ce then return nil,ce end;return true
end
local function loadLib(path)
 local src,e=fsRead(path,65536);if not src then return nil,e end
 local fn,le=load(src,'='..path,'t',_G);if not fn then return nil,le end
 local ok,r=pcall(fn);if not ok then return nil,r end;return r
end
local accel=first('luma_accelerator');local accelTier,accelBudget=0,1
if accel then local a,b=invoke(accel,'info');accelTier=tonumber(a) or 0;accelBudget=tonumber(b) or 1 end
local function memoryText()
 local free,total=PC.freeMemory(),PC.totalMemory()
 if total>=1024*1024 then return ('RAM %d/%dM'):format(math.floor(free/1048576),math.floor(total/1048576)) end
 return ('RAM %d/%dK'):format(math.floor(free/1024),math.floor(total/1024))
end
local function lumaRamKiB()
 local total=0
 for address in C.list('luma_memory') do local n=invoke(address,'capacity');total=total+(tonumber(n) or 0) end
 return total
end
local config={eco=true,accent='mint'}
local cfg=fsRead('/system/luma/settings.cfg',4096)
if cfg then for k,v in cfg:gmatch('([%a_]+)=([^\n]+)') do if k=='eco' then config.eco=v=='1' elseif k=='accent' then config.accent=v end end end
local page='home';local index=1;local message='';local messageUntil=0;local lastClock=-1;local running=true
local menu={{'Медиатека','media'},{'Файлы','files'},{'Приложения','apps'},{'Диагностика','diag'},{'Настройки','settings'}}

-- Horizon is optional at boot: direct rendering remains as the recovery path.
local Compositor=loadLib('/system/luma/lib/compositor.lua')
local Horizon=loadLib('/system/luma/lib/horizon.lua')
local LuVid=loadLib('/system/luma/lib/luvid.lua')
if depth==1 then
 if Horizon then for k in pairs(Horizon.theme) do Horizon.theme[k]=(k=='bg' or k=='panel' or k=='active') and 0 or 0xFFFFFF end end
 if LuVid then for i,c in ipairs(LuVid.palette) do
  local r,g,b=math.floor(c/65536)%256,math.floor(c/256)%256,c%256
  LuVid.palette[i]=(r*299+g*587+b*114>=128000) and 0xFFFFFF or 0
 end end
end
local Audio=loadLib('/system/luma/lib/audio.lua')
local VFS=loadLib('/system/luma/lib/vfs.lua')
local LuPackage=loadLib('/system/luma/lib/lupackage.lua')
local vfs
if VFS then local ok,result=pcall(VFS.new,C,boot,invoke);if ok then vfs=result end end
local comp,homeNodes,homeButtons,homeFocus,footerLabel
local systemNodes,systemButtons,systemFocus,systemFooter={},{},nil,nil
local filePath='/'
local listPages={files=0,media=0,apps=0};local listPageCount=1
local function header(title)
 fill(1,1,w,h,P.bg);fill(1,1,w,3,P.panel);text(3,2,'LUMA OS 3.0α',P.accent,P.panel);text(math.max(24,w-30),2,title or 'Главная',P.text,P.panel)
 fill(1,h-1,w,2,P.panel);text(2,h-1,message~='' and message or 'Стрелки: выбор · Enter: открыть · F1: домой',message~='' and P.accent or P.muted,P.panel,w-2)
 local hw=accelTier>0 and ('LumaChip L'..accelTier..' ×'..accelBudget) or 'STOCK';text(math.max(1,w-#hw-1),h,hw,accelTier>0 and P.accent or P.warn,P.panel)
end
local function button(y,label,selected)
 local b=selected and P.line or P.panel;fill(4,y,w-8,3,b);if selected then fill(4,y,1,3,P.accent) end;text(7,y+1,label,selected and P.accent or P.text,b,w-12)
end
local function hideHome() if homeNodes then for _,n in ipairs(homeNodes) do n.visible=false end end end
local function openPage(target) page=target;index=1;hideHome() end
local function buildHome()
 if not (Compositor and Horizon and C.proxy) then return false end
 local ok,gp=pcall(C.proxy,gpu);if not ok or not gp then return false end
 comp=Compositor.new(gp,w,h,Horizon.theme);homeNodes={};homeButtons={};homeFocus=Horizon.focus(comp)
 local function keep(n) homeNodes[#homeNodes+1]=n;return n end
 keep(Horizon.panel(comp,1,1,w,1,0,P.panel))
 keep(Horizon.label(comp,3,1,18,'LUMA',P.accent,P.panel,2))
 keep(Horizon.label(comp,math.max(24,math.floor(w/2)-3),1,12,'Главная',P.text,P.panel,2))
 local hw=accelTier>0 and ('LumaChip L'..accelTier) or 'STOCK'
 keep(Horizon.label(comp,math.max(2,w-#hw-1),1,#hw,hw,accelTier>0 and P.accent or P.warn,P.panel,2))
 keep(Horizon.label(comp,3,3,w-6,'Система работает без OpenOS',P.muted,P.bg,2))
 keep(Horizon.label(comp,3,4,w-6,accelTier>0 and 'Аппаратное ускорение активно' or 'Совместимый режим штатного оборудования',accelTier>0 and P.accent or P.warn,P.bg,2))
 local cols=w>=100 and 2 or 1;local gap=2;local bx=3;local bw=cols==2 and math.floor((w-bx*2-gap)/2) or w-bx*2
 local by=6;local step=h<22 and 1 or h<=25 and 3 or 4;local bh=h<22 and 1 or 3
 for i,m in ipairs(menu) do
  local col=(i-1)%cols;local row=math.floor((i-1)/cols)
  local target=m[2]
  local n=keep(Horizon.button(comp,bx+col*(bw+gap),by+row*step,bw,bh,m[1],function() openPage(target) end,3))
  homeButtons[#homeButtons+1]=n;homeFocus:add(n)
 end
 keep(Horizon.panel(comp,1,h,w,1,0,P.panel))
 footerLabel=keep(Horizon.label(comp,2,h,math.max(1,w-26),'Стрелки · Enter · F1',P.muted,P.panel,2))
 keep(Horizon.label(comp,math.max(2,w-22),h,20,memoryText(),P.accent,P.panel,2))
 return true
end
local horizonReady=buildHome()
local function showHome(full)
 page='home';if not horizonReady then return false end
 for _,n in ipairs(homeNodes) do n.visible=true end
 footerLabel.text=message~='' and message or 'Стрелки · Enter · F1'
 if full then comp:invalidateAll() end
 comp:flush();return true
end
local function drawHome() if not showHome(true) then header('Главная');local y=6;for i,m in ipairs(menu) do button(y+(i-1)*3,m[1],i==index) end end end
local function clearSystem()
 if not comp then return end
 for _,n in ipairs(systemNodes) do comp:remove(n) end
 systemNodes={};systemButtons={};systemFocus=nil;systemFooter=nil
end
local buildSystem
local function mediaFiles()
 local out={}
 local function scan(dir)
  local list=fsList(dir)
  for _,name in ipairs(list) do if name:lower():match('%.lvd$') then out[#out+1]={name=name,path=(dir=='/' and '/' or dir..'/')..name} end end
 end
 scan('/media');if #out==0 then scan('/') end
 return out
end
local function playLuVid(path)
 if not LuVid then message='Media Core повреждён или не установлен';messageUntil=PC.uptime()+4;return end
 local hnd,e=fsOpen(path,'r');if not hnd then message='Не открыть '..path..': '..tostring(e);messageUntil=PC.uptime()+4;return end
 local reader={}
 function reader:read(n) return invoke(boot,'read',hnd,n) end
 function reader:seek(whence,n) return invoke(boot,'seek',hnd,whence,n) end
 function reader:close() local ok,er=invoke(boot,'close',hnd);hnd=nil;return ok,er end
 local decoder=accel and {decodeRLE=function(data,n) return invoke(accel,'decodeRLE',data,n) end} or nil
 local video,er=LuVid.open(reader,decoder)
 if not video then reader:close();message='LuVid: '..tostring(er);messageUntil=PC.uptime()+4;return end
 clearSystem();fill(1,1,w,h,P.bg)
 local tape=first('tape_drive');local audioCard=first('audio');local audioStream;local audioReady=false;local audioLabel=video.audioBytes>0 and 'звук отключён' or 'без аудио'
 if video.audioBytes>0 and audioCard and Audio then
  text(2,2,'Подготовка потокового DFPWM audio…',P.accent,P.bg,w-2)
  local at,ae=video:scanAudio()
  if at then
   local ah,err=fsOpen(path,'r')
   if ah then
    invoke(boot,'seek',ah,'set',at)
    local ar={read=function(_,n) return invoke(boot,'read',ah,n) end,close=function() if ah then invoke(boot,'close',ah);ah=nil end end}
    audioStream=Audio.new(invoke,audioCard,ar,video.audioBytes,PC.uptime)
    local ready,why=pcall(function() audioStream:start() end)
    if ready then audioLabel='DFPWM · OC Audio · поток 32 KiB' else audioStream:close();audioStream=nil;audioLabel='аудио: '..tostring(why) end
   else audioLabel='аудио: '..tostring(err) end
   video:rewind()
  else audioLabel='аудио: '..tostring(ae) end
 elseif video.audioBytes>0 and tape then
  local ready=invoke(tape,'isReady');local capacity=ready and tonumber(invoke(tape,'getSize')) or 0
  if not ready then audioLabel='вставьте кассету'
  elseif video.audioBytes>capacity then audioLabel='аудио длиннее кассеты'
  else
   text(2,2,'Подготовка DFPWM audio…',P.accent,P.bg,w-2)
   local audioAt,ae=video:scanAudio()
   if audioAt then
    invoke(tape,'stop');local pos=tonumber(invoke(tape,'getPosition')) or 0;invoke(tape,'seek',-pos)
    reader:seek('set',audioAt);local left=video.audioBytes;local loaded=0
    while left>0 do
     local chunk,re=reader:read(math.min(8192,left));if not chunk or #chunk==0 then ae=re or 'аудио обрезано';break end
     local wrote,we=invoke(tape,'write',chunk);if wrote==nil and we then ae=we;break end
     left=left-#chunk;loaded=loaded+#chunk
     if loaded%65536<8192 then text(2,3,('%d%%'):format(math.floor(loaded*100/video.audioBytes)),P.muted,P.bg,8) end
    end
    video:rewind();pos=tonumber(invoke(tape,'getPosition')) or 0;invoke(tape,'seek',-pos)
    if left==0 then audioReady=true;audioLabel='DFPWM tape audio clock' else audioLabel='ошибка аудио: '..tostring(ae) end
   else audioLabel='ошибка аудио: '..tostring(ae) end
  end
 end
 local paused,stop=false,false;local nextAt=PC.uptime();local lastFrame;local dropped=0
 local ok,why=pcall(function()
  if audioReady then invoke(tape,'setSpeed',1);invoke(tape,'play') end
  while not stop do
   local now=PC.uptime()
   if audioStream and not paused then
    if not audioStream:pump() then audioStream:close();audioStream=nil;audioLabel='DFPWM завершён';nextAt=now end
   end
   if not paused and now>=nextAt then
    local desired
    if audioStream then
     desired=math.min(video.count,math.floor(audioStream:position()*video.fps)+1);nextAt=now+.02
    elseif audioReady then
     local apos=tonumber(invoke(tape,'getPosition')) or 0;desired=math.min(video.count,math.floor(apos/6000*video.fps)+1);nextAt=now+.02
     if apos>=video.audioBytes then audioReady=false;audioLabel='DFPWM завершён';desired=math.min(video.count,video.index+1);nextAt=now+1/video.fps end
    else
     desired=math.min(video.count,video.index+1+math.max(0,math.floor((now-nextAt)*video.fps)));nextAt=nextAt+(desired-video.index)/video.fps
    end
    while video.index+1<desired do local skipped,se=video:skipFrame();if not skipped then error(se,0) end;dropped=dropped+1 end
    if desired>video.index then
     local frame,fe=video:nextFrame();if not frame then if fe=='end' then break else error(fe,0) end end
     lastFrame=frame;fill(1,1,w,h-2,P.bg);LuVid.draw(comp.gpu,frame,video.w,video.h,1,2,w,h-4)
     fill(1,1,w,1,P.panel);text(2,1,('LuVid · %s · %d/%d · %s · drop %d'):format(path,video.index,video.count,video.backend,dropped),P.accent,P.panel,w-2)
     fill(1,h-1,w,2,P.panel);text(2,h-1,'Space: пауза · Esc/F1: медиатека',P.muted,P.panel,w-2)
     text(2,h,audioLabel,(audioReady or audioStream) and P.accent or P.muted,P.panel,w-2)
    elseif video.index>=video.count and not audioStream and not audioReady then break end
   end
   local timeout=paused and .25 or math.max(0,math.min(.1,nextAt-PC.uptime()))
   local ev={PC.pullSignal(timeout)}
   if ev[1]=='key_down' then
    local key=ev[4]
    if key==1 or key==59 then stop=true
    elseif key==57 then
     paused=not paused
     if audioStream then audioStream:setPaused(paused) end
     if audioReady then if paused then invoke(tape,'stop') else invoke(tape,'play') end end
     if not paused then nextAt=PC.uptime()+1/video.fps elseif lastFrame then fill(1,h,w,1,P.panel);text(2,h,'Пауза',P.warn,P.panel,w-2) end
    end
   end
  end
 end)
 if audioStream then audioStream:close() end
 if audioReady then invoke(tape,'stop');local pos=tonumber(invoke(tape,'getPosition')) or 0;invoke(tape,'seek',-pos) end
 video:close()
 message=ok and 'Воспроизведение завершено' or ('Ошибка LuVid: '..tostring(why));messageUntil=PC.uptime()+4
 page='media';buildSystem('media')
end
local function installedApps()
 local out={};if not LuPackage then return out end
 for _,dir in ipairs(fsList('/apps')) do
  local clean=dir:gsub('/$','');local base='/apps/'..clean;local raw=fsRead(base..'/manifest.cfg',8192)
  if raw then local manifest=LuPackage.manifest(raw);if manifest then manifest.base=base;out[#out+1]=manifest end end
 end
 table.sort(out,function(a,b)return a.name:lower()<b.name:lower()end);return out
end
local function runApp(app)
 local source,e=fsRead(app.base..'/'..app.entry,65536);if not source then message='Приложение: '..tostring(e);messageUntil=PC.uptime()+4;return end
 clearSystem()
 local function need(permission) if not app.permissions[permission] then error('нет разрешения '..permission,2) end end
 local api={width=w,height=h,accent=P.accent,muted=P.muted}
 function api.clear() need('screen');fill(1,1,w,h,P.bg) end
 function api.title(s) need('screen');fill(1,1,w,1,P.panel);text(3,1,s,P.accent,P.panel,w-4) end
 function api.center(y,s,c) need('screen');center(y,s,c or P.text,P.bg) end
 function api.text(x,y,s,c) need('screen');text(x,y,s,c or P.text,P.bg,w-x+1) end
 function api.uptime() return PC.uptime() end
 function api.input(timeout) need('input');local e={PC.pullSignal(timeout)};return e[1],e[4],e end
 local runner,le=LuPackage.load(source,'='..app.base..'/'..app.entry,api)
 local ok,why;if runner then ok,why=runner() else ok,why=nil,le end
 message=ok and (app.name..' закрыто') or ('Сбой '..app.name..': '..tostring(why or le));messageUntil=PC.uptime()+5
 page='apps';buildSystem('apps')
end
buildSystem=function(target)
 if not horizonReady then return false end
 clearSystem()
 local function keep(n) systemNodes[#systemNodes+1]=n;return n end
 local titles={diag='Диагностика',files='Файлы',settings='Настройки',media='Медиатека',apps='Приложения'}
 local title=titles[target] or target;listPageCount=1
 keep(Horizon.panel(comp,1,1,w,1,0,P.panel))
 keep(Horizon.label(comp,3,1,18,'LUMA OS 3.0α',P.accent,P.panel,2))
 keep(Horizon.label(comp,math.max(24,w-30),1,28,title,P.text,P.panel,2))
 keep(Horizon.panel(comp,1,h,w,1,0,P.panel))
 systemFooter=keep(Horizon.label(comp,2,h,w-4,message~='' and message or 'Стрелки · Enter · F1: домой',message~='' and P.accent or P.muted,P.panel,2))
 local function listRange(total)
  local a,b,page,pages=Horizon.page(total,h,listPages[target]);listPages[target]=page;listPageCount=pages
  if pages>1 and message=='' then systemFooter.text=('PgUp/PgDn %d/%d · Enter · F1'):format(page+1,pages) end
  return a,b
 end
 if target=='diag' then
  local lr=lumaRamKiB()
  local rows={{'Загрузочный диск',boot},{'GPU depth',depth..' / '..maxDepth},{'Разрешение',w..' × '..h},{'RAM свободно',math.floor(PC.freeMemory()/1024)..' KiB'},{'RAM всего',math.floor(PC.totalMemory()/1024)..' KiB'},{'Luma RAM',lr>0 and (math.floor(lr/1024)..' MiB') or 'не установлена'},{'Ускоритель',accelTier>0 and ('LumaChip L'..accelTier) or 'stock fallback'},{'Call budget',accelBudget},{'Компонентов',0}}
  local count=0;for _ in C.list() do count=count+1 end;rows[#rows][2]=count
  if vfs then local disks=vfs:health();local free=0;for _,d in ipairs(disks) do free=free+d.free end;rows[#rows+1]={'VFS дисков / свободно',#disks..' / '..math.floor(free/1024)..' KiB'} end
  local step=h<22 and 1 or h<30 and 2 or 3
  for i,r in ipairs(rows) do local y=3+(i-1)*step;keep(Horizon.label(comp,4,y,math.floor(w*.42)-5,r[1],P.muted,P.bg,2));keep(Horizon.label(comp,math.floor(w*.42),y,math.floor(w*.55),tostring(r[2]),P.text,P.bg,2)) end
 elseif target=='files' then
  keep(Horizon.label(comp,4,3,w-8,'VFS · '..filePath,P.muted,P.bg,2))
  local list=vfs and (vfs:list(filePath) or {}) or {};systemFocus=Horizon.focus(comp)
  if filePath~='/' then table.insert(list,1,{name='../',path=filePath:match('^(.+)/[^/]+$') or '/',dir=true,parent=true}) end
  if #list==0 then keep(Horizon.label(comp,5,6,w-10,vfs and 'Пусто' or 'VFS не загружен',P.warn,P.bg,2)) end
  local firstRow,lastRow=listRange(#list)
  for i=firstRow,lastRow do
   local item=list[i]
   local suffix=item.dir and '' or (' · '..math.floor((item.size or 0)/1024)..' KiB')
   local n=keep(Horizon.button(comp,4,4+(i-firstRow)*3,w-8,3,item.name..suffix,function()
    if item.dir then filePath=item.path;listPages.files=0;buildSystem('files')
    else message=item.path..' · '..tostring(item.size or 0)..' bytes · Del: в корзину';messageUntil=PC.uptime()+4;systemFooter.text=message;comp:invalidate(systemFooter) end
   end,3));n.vfsItem=item
   systemButtons[#systemButtons+1]=n;systemFocus:add(n)
  end
 elseif target=='media' then
  keep(Horizon.label(comp,4,3,w-8,'LUVID · /media',P.muted,P.bg,2))
  local files=mediaFiles();systemFocus=Horizon.focus(comp)
  if #files==0 then keep(Horizon.label(comp,5,6,w-10,'Файлы .lvd не найдены в /media или /',P.warn,P.bg,2)) end
  local firstRow,lastRow=listRange(#files)
  for i=firstRow,lastRow do
   local item=files[i]
   local n=keep(Horizon.button(comp,4,4+(i-firstRow)*3,w-8,3,item.name,function() playLuVid(item.path) end,3))
   systemButtons[#systemButtons+1]=n;systemFocus:add(n)
  end
 elseif target=='apps' then
  keep(Horizon.label(comp,4,3,w-8,'LUPACKAGE · /apps',P.muted,P.bg,2))
  local apps=installedApps();systemFocus=Horizon.focus(comp)
  if #apps==0 then keep(Horizon.label(comp,5,6,w-10,LuPackage and 'Приложения не установлены' or 'LuPackage runtime не загружен',P.warn,P.bg,2)) end
  local firstRow,lastRow=listRange(#apps)
  for i=firstRow,lastRow do
   local app=apps[i]
   local n=keep(Horizon.button(comp,4,4+(i-firstRow)*3,w-8,3,app.name..' · '..app.version,function() runApp(app) end,3))
   systemButtons[#systemButtons+1]=n;systemFocus:add(n)
  end
 elseif target=='settings' then
  keep(Horizon.label(comp,4,3,w-8,'ПРОИЗВОДИТЕЛЬНОСТЬ И ПИТАНИЕ',P.muted,P.bg,2));systemFocus=Horizon.focus(comp)
  local sy,sgap=h<22 and 4 or 5,h<22 and 3 or 4
  local eco
  eco=keep(Horizon.button(comp,4,sy,w-8,3,'Экономный режим: '..(config.eco and 'включён' or 'выключен'),function(n)
   config.eco=not config.eco;n:setLabel('Экономный режим: '..(config.eco and 'включён' or 'выключен'))
   local ok,e=fsWrite('/system/luma/settings.cfg',('eco=%d\naccent=%s\n'):format(config.eco and 1 or 0,config.accent))
   message=ok and 'Настройки сохранены' or ('Не удалось сохранить: '..tostring(e));messageUntil=PC.uptime()+3;systemFooter.text=message;comp:invalidate(systemFooter)
  end,3))
  local safe=keep(Horizon.button(comp,4,sy+sgap,w-8,3,'Безопасная глубина: '..depth,nil,3));safe.enabled=false
  local reboot=keep(Horizon.button(comp,4,sy+sgap*2,w-8,3,'Перезагрузить компьютер',function() PC.shutdown(true) end,3))
  local shutdown=keep(Horizon.button(comp,4,sy+sgap*3,w-8,3,'Выключить компьютер',function() PC.shutdown(false) end,3))
  for _,n in ipairs({eco,reboot,shutdown}) do systemButtons[#systemButtons+1]=n;systemFocus:add(n) end
 end
 comp:invalidateAll();comp:flush();return true
end
local function drawDiag()
 header('Диагностика');local lr=lumaRamKiB();local rows={{'Загрузочный диск',boot},{'GPU depth',depth..' / reported '..maxDepth},{'Разрешение',w..' × '..h},{'RAM свободно',math.floor(PC.freeMemory()/1024)..' KiB'},{'RAM всего',math.floor(PC.totalMemory()/1024)..' KiB'},{'Luma RAM',lr>0 and (math.floor(lr/1024)..' MiB detected') or 'не установлена'},{'Ускоритель',accelTier>0 and ('LumaChip L'..accelTier) or 'нет — stock fallback'},{'Call budget',accelBudget},{'Компонентов',0}}
 local count=0;for _ in C.list() do count=count+1 end;rows[#rows][2]=count
 local step=h<22 and 1 or h<30 and 2 or 3
 for i,r in ipairs(rows) do local y=4+(i-1)*step;text(4,y,r[1],P.muted);text(math.floor(w*.42),y,tostring(r[2]),P.text,nil,math.floor(w*.56)) end
end
local function drawFiles()
 header('Файлы');local list=fsList('/');text(4,5,'Корень загрузочного диска',P.muted);if #list==0 then text(4,8,'Пусто',P.warn) else for i=1,math.min(#list,h-9) do text(5,6+i,(i==index and '> ' or '  ')..list[i],i==index and P.accent or P.text) end end
end
local function drawSettings()
 header('Настройки');text(4,5,'ПРОИЗВОДИТЕЛЬНОСТЬ',P.muted);button(7,'Экономный режим: '..(config.eco and 'включён' or 'выключен'),index==1);button(11,'Безопасная глубина: '..depth,index==2);button(15,'Перезагрузить компьютер',index==3);button(19,'Выключить компьютер',index==4)
end
local function drawPlaceholder(title,body) header(title);center(math.floor(h/2)-1,title,P.accent);center(math.floor(h/2)+1,body,P.muted) end
local function draw()
 if page=='home' then drawHome() elseif buildSystem(page) then return elseif page=='diag' then drawDiag() elseif page=='files' then drawFiles() elseif page=='settings' then drawSettings() elseif page=='media' then drawPlaceholder('Медиатека','LuVid runtime подключается следующим модулем') else drawPlaceholder('Приложения','LuPackage runtime подключается следующим модулем') end
end
local function home() index=1;clearSystem();if not showHome(true) then page='home';draw() end end
local function activate()
 if page=='home' then
  if horizonReady then homeFocus:activate();draw() else openPage(menu[index][2]);draw() end
 elseif horizonReady and systemFocus then systemFocus:activate();comp:flush()
 elseif page=='settings' then
  if index==1 then config.eco=not config.eco;message='Режим изменён для текущей сессии';messageUntil=PC.uptime()+3;draw()
  elseif index==3 then PC.shutdown(true) elseif index==4 then PC.shutdown(false) end
 end
end
local function move(d)
 if page=='home' and horizonReady then homeFocus:move(0,d);comp:flush();return end
 if horizonReady and systemFocus then systemFocus:move(0,d);comp:flush();return end
 local max=page=='home' and #menu or page=='settings' and 4 or page=='files' and math.max(1,#fsList('/')) or 1
 index=((index-1+d)%max)+1;draw()
end
local function mainLoop()
 draw()
 while running do
  local timeout=config.eco and .25 or .05;local e={PC.pullSignal(timeout)};local name=e[1]
  if name=='key_down' then
   local key=e[4]
   if page=='home' and horizonReady and key==203 then homeFocus:move(-1,0);comp:flush()
   elseif page=='home' and horizonReady and key==205 then homeFocus:move(1,0);comp:flush()
   elseif page=='files' and horizonReady and (key==14 or key==203) and filePath~='/' then filePath=filePath:match('^(.+)/[^/]+$') or '/';listPages.files=0;buildSystem('files')
   elseif page=='files' and horizonReady and key==211 and systemFocus and systemFocus.current and systemFocus.current.vfsItem then
    local item=systemFocus.current.vfsItem
    if item.parent then message='Родительскую папку удалить нельзя'
    else local removed,why=vfs:trash(item.path,math.floor(PC.uptime()*1000));message=removed and ('Перемещено в корзину: '..item.name) or ('Не удалено: '..tostring(why)) end
    messageUntil=PC.uptime()+4;buildSystem('files')
   elseif horizonReady and listPages[page] and (key==201 or key==209) then listPages[page]=listPages[page]+(key==201 and -1 or 1);buildSystem(page)
   elseif key==200 then move(-1) elseif key==208 then move(1) elseif key==28 then activate() elseif key==59 then home() elseif key==1 and page~='home' then home() end
  elseif name=='component_added' or name=='component_removed' then
   if e[3]=='filesystem' and VFS then
    local ok,new=pcall(VFS.new,C,boot,invoke)
    if ok then
     vfs=new
     if filePath~='/' and not vfs:stat(filePath) then filePath='/mnt' end
     if page=='files' or page=='diag' then draw() end
    end
   end
  elseif name=='touch' then
   local tx,ty=e[3],e[4]
   if horizonReady then
    local wasHome=page=='home';local buttons=wasHome and homeButtons or systemButtons;local focus=wasHome and homeFocus or systemFocus
    for _,n in ipairs(buttons) do if tx>=n.x and tx<n.x+n.w and ty>=n.y and ty<n.y+n.h then focus:set(n);comp:flush();n:activate();if wasHome then draw() else comp:flush() end;break end end
   elseif page=='home' then local row=math.floor((ty-6)/3)+1;if row>=1 and row<=#menu then index=row;activate() end end
  end
  local tick=math.floor(PC.uptime()/5)
  if tick~=lastClock then lastClock=tick;if message~='' and PC.uptime()>messageUntil then message='';if page=='home' then showHome(true) else draw() end end end
 end
end
local function trace(e) return debug and debug.traceback(tostring(e),2) or tostring(e) end
local ok,crash=xpcall(mainLoop,trace)
if not ok then
 fsWrite('/system/luma/crash.log',('Luma OS crash\nuptime=%.3f\npage=%s\n%s\n'):format(PC.uptime(),tostring(page),tostring(crash)))
 fill(1,1,w,h,P.danger);text(3,2,'LUMA OS · CRASH SCREEN',P.bg,P.danger,w-4)
 text(3,4,'Ошибка сохранена: /system/luma/crash.log',P.bg,P.danger,w-4)
 local row=6
 for line in tostring(crash):gmatch('[^\n]+') do if row>=h-2 then break end;text(3,row,line,P.bg,P.danger,w-4);row=row+1 end
 text(3,h-1,'Enter: перезагрузить · Esc: выключить',P.bg,P.danger,w-4)
 while true do local e={PC.pullSignal()};if e[1]=='key_down' then if e[4]==28 then PC.shutdown(true) elseif e[4]==1 then PC.shutdown(false) end end end
end
]==])
write('/system/luma/lib/compositor.lua',[==[-- Luma Horizon compositor v1. Retained nodes + dirty rectangles, no full framebuffer.
local M={}
local U=rawget(_G,'unicode')
local function ulen(s) return U and U.len(s) or #s end
local function usub(s,a,b) return U and U.sub(s,a,b) or s:sub(a,b) end
local function intersects(a,b) return a.x<b.x+b.w and b.x<a.x+a.w and a.y<b.y+b.h and b.y<a.y+a.h end
local function union(a,b) local x=math.min(a.x,b.x);local y=math.min(a.y,b.y);return{x=x,y=y,w=math.max(a.x+a.w,b.x+b.w)-x,h=math.max(a.y+a.h,b.y+b.h)-y} end
local function clamp(r,w,h)
 local x=math.max(1,math.floor(r.x));local y=math.max(1,math.floor(r.y));local x2=math.min(w+1,math.ceil(r.x+r.w));local y2=math.min(h+1,math.ceil(r.y+r.h))
 if x2<=x or y2<=y then return nil end;return{x=x,y=y,w=x2-x,h=y2-y}
end
function M.new(gpu,w,h,theme)
 local self={gpu=gpu,w=w,h=h,theme=theme,nodes={},dirty={},nextId=1,stats={frames=0,fills=0,texts=0,nodes=0,dirtyArea=0}}
 function self:add(node)
  node.id=self.nextId;self.nextId=self.nextId+1;node.z=node.z or 0;node.visible=node.visible~=false;self.nodes[#self.nodes+1]=node
  table.sort(self.nodes,function(a,b) return a.z==b.z and a.id<b.id or a.z<b.z end);self:invalidate(node);return node
 end
 function self:remove(node) for i,n in ipairs(self.nodes) do if n==node then table.remove(self.nodes,i);self:invalidate(node);break end end end
 function self:invalidate(r)
  r=clamp(r,self.w,self.h);if not r then return end
  for i,d in ipairs(self.dirty) do
   local near={x=d.x-1,y=d.y-1,w=d.w+2,h=d.h+2}
   if intersects(near,r) then self.dirty[i]=union(d,r);return end
  end
  self.dirty[#self.dirty+1]=r
 end
 function self:invalidateAll() self.dirty={{x=1,y=1,w=self.w,h=self.h}} end
 local function clipRect(a,b)
  local x=math.max(a.x,b.x);local y=math.max(a.y,b.y);local x2=math.min(a.x+a.w,b.x+b.w);local y2=math.min(a.y+a.h,b.y+b.h)
  if x2<=x or y2<=y then return nil end;return{x=x,y=y,w=x2-x,h=y2-y}
 end
 function self:fill(rect,bg)
  if rect.w<=0 or rect.h<=0 then return end;self.gpu.setBackground(bg);self.gpu.fill(rect.x,rect.y,rect.w,rect.h,' ');self.stats.fills=self.stats.fills+1
 end
 function self:text(rect,x,y,s,fg,bg)
  if y<rect.y or y>=rect.y+rect.h then return end;local left=math.max(rect.x,x);local right=math.min(rect.x+rect.w,x+ulen(s));if right<=left then return end
  local from=left-x+1;local part=usub(s,from,from+right-left-1);self.gpu.setForeground(fg);self.gpu.setBackground(bg);self.gpu.set(left,y,part);self.stats.texts=self.stats.texts+1
 end
 function self:flush()
  if #self.dirty==0 then return false end
  self.stats.frames=self.stats.frames+1;self.stats.fills=0;self.stats.texts=0;self.stats.nodes=0;self.stats.dirtyArea=0
  local dirty=self.dirty;self.dirty={}
  for _,r in ipairs(dirty) do
   self.stats.dirtyArea=self.stats.dirtyArea+r.w*r.h;self:fill(r,self.theme.bg)
   for _,node in ipairs(self.nodes) do if node.visible and intersects(node,r) then local c=clipRect(node,r);if c and node.draw then node.draw(self,c);self.stats.nodes=self.stats.nodes+1 end end end
  end
  return true
 end
 return self
end
return M
]==])
write('/system/luma/lib/horizon.lua',[==[-- Luma Horizon widgets and directional focus graph.
local M={}
-- Pure, bounded page geometry, shared by files, media, and applications.
function M.page(total,height,requested)
 local rows=math.max(1,math.floor((height-5)/3))
 local pages=math.max(1,math.ceil(total/rows));local page=math.max(0,math.min(pages-1,math.floor(requested or 0)))
 return page*rows+1,math.min(total,(page+1)*rows),page,pages
end

M.theme={bg=0x0D131E,panel=0x172231,active=0x294654,text=0xE5ECF6,muted=0x8195AE,accent=0x8EDBD3,warn=0xF3CD78,danger=0xF4A99C}
local U=rawget(_G,'unicode')
local function ulen(s) return U and U.len(s) or #s end
local function usub(s,a,b) return U and U.sub(s,a,b) or s:sub(a,b) end
local function clip(s,n) if ulen(s)<=n then return s end;return n>1 and usub(s,1,n-1)..'…' or usub(s,1,n) end
function M.panel(c,x,y,w,h,z,color)
 return c:add{x=x,y=y,w=w,h=h,z=z or 0,draw=function(cc,r) cc:fill(r,color or cc.theme.panel) end}
end
function M.label(c,x,y,w,text,fg,bg,z)
 local n={x=x,y=y,w=w,h=1,z=z or 1,text=text,draw=function(self,cc) end}
 n.draw=function(cc,r) cc:text(r,x,y,clip(tostring(n.text or ''),w),fg or cc.theme.text,bg or cc.theme.bg) end
 return c:add(n)
end
function M.button(c,x,y,w,h,label,action,z)
 local n={x=x,y=y,w=w,h=h,z=z or 2,label=label,action=action,focusable=true,focused=false,enabled=true}
 n.draw=function(cc,r)
  local bg=n.focused and cc.theme.active or cc.theme.panel;cc:fill(r,bg)
  if n.focused then local bar={x=x,y=math.max(y,r.y),w=1,h=math.min(y+h,r.y+r.h)-math.max(y,r.y)};if bar.h>0 then cc:fill(bar,cc.theme.accent) end end
  local yy=y+math.floor((h-1)/2);cc:text(r,x+3,yy,clip(n.label,w-5),n.enabled and (n.focused and cc.theme.accent or cc.theme.text) or cc.theme.muted,bg)
 end
 function n:setFocused(v) if self.focused~=v then self.focused=v;c:invalidate(self) end end
 function n:setLabel(v) if self.label~=v then self.label=v;c:invalidate(self) end end
 function n:activate() if self.enabled and self.action then return self.action(self) end end
 return c:add(n)
end
function M.focus(c)
 local f={items={},current=nil}
 function f:add(node) self.items[#self.items+1]=node;if not self.current then self.current=node;node:setFocused(true) end;return node end
 function f:set(node) if node==self.current then return end;if self.current then self.current:setFocused(false) end;self.current=node;if node then node:setFocused(true) end end
 function f:move(dx,dy)
  local cur=self.current;if not cur then return end;local cx,cy=cur.x+cur.w/2,cur.y+cur.h/2;local best,score
  for _,n in ipairs(self.items) do if n~=cur and n.visible~=false and n.enabled~=false then local nx,ny=n.x+n.w/2,n.y+n.h/2;local vx,vy=nx-cx,ny-cy
   if (dx<0 and vx<0)or(dx>0 and vx>0)or(dy<0 and vy<0)or(dy>0 and vy>0) then
    local primary=dx~=0 and math.abs(vx) or math.abs(vy);local cross=dx~=0 and math.abs(vy) or math.abs(vx);local s=primary+cross*2
    if not score or s<score then best,score=n,s end
   end
  end end;if best then self:set(best);return true end
 end
 function f:activate() return self.current and self.current:activate() end
 return f
end
return M
]==])
write('/system/luma/lib/luvid.lua',[==[-- LuVid LVD1 streaming core for bare-metal Luma OS.
-- No OpenOS/io dependency: callers provide a reader with read/seek/close.
local M={}
M.palette={0x0D131E,0x172231,0x294654,0x428995,0x8EDBD3,0xE5ECF6,0x4D80CD,0x8ABAF0,0x66B09F,0xB6E8D8,0x9D88C5,0xD0C5E8,0xC28E3F,0xF3CD78,0x8195AE,0xF4A99C}

local function exact(r,n)
 local out,left={},n
 while left>0 do
  local s,e=r:read(left)
  if not s or #s==0 then return nil,e or 'unexpected end of file' end
  out[#out+1]=s;left=left-#s
 end
 return table.concat(out)
end
local function line(r,limit)
 local out={}
 for _=1,limit do
  local s,e=exact(r,1);if not s then return nil,e end
  if s=='\n' then return table.concat(out) end
  out[#out+1]=s
 end
 return nil,'header line too long'
end
local function u32be(s) return s:byte(1)*16777216+s:byte(2)*65536+s:byte(3)*256+s:byte(4) end

function M.decodeRLE(src,expected,accelerator)
 if accelerator and accelerator.decodeRLE then
  local ok,out=pcall(accelerator.decodeRLE,src,expected)
  if ok and type(out)=='string' and #out==expected then return out,'hardware' end
 end
 local out,n={},0
 local at=1
 while at<=#src and n<expected do
  local tag=src:byte(at);at=at+1
  if tag<128 then
   local count=tag+1
   if at+count-1>#src then return nil,'truncated LVD literal' end
   local chunk=src:sub(at,at+count-1)
   for i=1,#chunk do if chunk:byte(i)>15 then return nil,'invalid LVD palette index' end end
   out[#out+1]=chunk;n=n+count;at=at+count
  else
   local count=tag-127;local value=src:byte(at);at=at+1
   if not value then return nil,'truncated LVD run' end
   if value>15 then return nil,'invalid LVD palette index' end
   out[#out+1]=string.rep(string.char(value),count);n=n+count
  end
  if n>expected then return nil,'LVD frame is too long' end
 end
 if n~=expected or at~=#src+1 then return nil,'wrong LVD frame length' end
 return table.concat(out),'software'
end

function M.open(reader,accelerator)
 assert(type(reader)=='table' and reader.read,'LuVid reader required')
 local magic,e=line(reader,8);if not magic then return nil,e end
 if magic~='LVD1' then return nil,'not an LVD1 file' end
 local hdr;hdr,e=line(reader,96);if not hdr then return nil,e end
 local w,h,fps,count,audio=hdr:match('^(%d+) (%d+) (%d+) (%d+) (%d+)$')
 w,h,fps,count,audio=tonumber(w),tonumber(h),tonumber(fps),tonumber(count),tonumber(audio)
 if not(w and h and fps and count and audio and w>=1 and w<=320 and h>=1 and h<=320 and fps>=1 and fps<=15 and count>=1 and count<=1000000 and audio>=0 and audio<=5368709120) then return nil,'invalid LVD1 header' end
 local dataAt=reader.seek and reader:seek('cur',0) or nil
 local obj={w=w,h=h,fps=fps,count=count,audioBytes=audio,index=0,reader=reader,accelerator=accelerator,backend='software',dataAt=dataAt}
 function obj:nextFrame()
  if self.index>=self.count then return nil,'end' end
  local b,er=exact(self.reader,4);if not b then return nil,er end
  local size=u32be(b)
  if size<1 or size>self.w*self.h*2+1024 then return nil,'invalid LVD frame size' end
  local encoded;encoded,er=exact(self.reader,size);if not encoded then return nil,er end
  local pixels,backend=M.decodeRLE(encoded,self.w*self.h,self.accelerator)
  if not pixels then return nil,backend end
  self.index=self.index+1;self.backend=backend
  return pixels
 end
 function obj:skipFrame()
  if self.index>=self.count then return nil,'end' end
  local b,er=exact(self.reader,4);if not b then return nil,er end
  local size=u32be(b);if size<1 or size>self.w*self.h*2+1024 then return nil,'invalid LVD frame size' end
  if self.reader.seek then
   local at,se=self.reader:seek('cur',size);if at==nil then return nil,se end
  else local ignored;ignored,er=exact(self.reader,size);if not ignored then return nil,er end end
  self.index=self.index+1;return true
 end
 function obj:rewind()
  if not self.dataAt or not self.reader.seek then return nil,'reader is not seekable' end
  local at,er=self.reader:seek('set',self.dataAt);if at==nil then return nil,er end
  self.index=0;return true
 end
 function obj:scanAudio()
  if not self.dataAt or not self.reader.seek then return nil,'reader is not seekable' end
  local saved=self.reader:seek('cur',0);local ok,er=self.reader:seek('set',self.dataAt)
  if ok==nil then return nil,er end
  for _=1,self.count do
   local b,e2=exact(self.reader,4);if not b then self.reader:seek('set',saved);return nil,e2 end
   local size=u32be(b);if size<1 or size>self.w*self.h*2+1024 then self.reader:seek('set',saved);return nil,'invalid LVD frame size' end
   local moved,e3=self.reader:seek('cur',size);if moved==nil then self.reader:seek('set',saved);return nil,e3 end
  end
  local audioAt=self.reader:seek('cur',0);self.reader:seek('set',saved);self.audioAt=audioAt;return audioAt
 end
 function obj:close() if self.reader then pcall(self.reader.close,self.reader);self.reader=nil end end
 return obj
end

-- Draw indexed pixels using upper-half blocks. Consecutive cells with the same
-- foreground/background are batched into one GPU set call.
function M.draw(gpu,pixels,sw,sh,x,y,vw,vh)
 local scale=math.min(vw/sw,(vh*2)/sh)
 local dw=math.max(1,math.floor(sw*scale));local ph=math.max(2,math.floor(sh*scale));local dh=math.max(1,math.floor(ph/2))
 local ox=x+math.floor((vw-dw)/2);local oy=y+math.floor((vh-dh)/2)
 local calls=0
 for cy=0,dh-1 do
  local runFg,runBg,runX,runN
  local function flush()
   if runN and runN>0 then gpu.setForeground(runFg);gpu.setBackground(runBg);gpu.set(runX,oy+cy,string.rep('▀',runN));calls=calls+3 end
  end
  for cx=0,dw-1 do
   local sx=math.min(sw-1,math.floor(cx*sw/dw))
   local sy1=math.min(sh-1,math.floor((cy*2)*sh/(dh*2)))
   local sy2=math.min(sh-1,math.floor((cy*2+1)*sh/(dh*2)))
   local fg=M.palette[pixels:byte(sy1*sw+sx+1)+1];local bg=M.palette[pixels:byte(sy2*sw+sx+1)+1]
   if fg==runFg and bg==runBg then runN=runN+1 else flush();runFg,runBg,runX,runN=fg,bg,ox+cx,1 end
  end
  flush()
 end
 return {x=ox,y=oy,w=dw,h=dh,gpuCalls=calls}
end
return M]==])
write('/system/luma/lib/audio.lua',[==[-- Bounded DFPWM -> OpenComputers audio-card streaming. No OpenOS dependency.
local M={}
function M.decoder()
 local response,level,last,flast,low=0,0,false,0,0
 return function(src)
  local out={}
  for i=1,#src do
   local d=src:byte(i)
   for _=1,8 do
    local bit=d%2==1;d=math.floor(d/2)
    local target=bit and 127 or -128
    local n=level+math.floor((response*(target-level)+512)/1024)
    if n==level and n~=target then n=n+(bit and 1 or -1) end
    local same=bit==last
    local rt=same and 1023 or 0
    if response~=rt then response=response+(same and 1 or -1) end
    response=math.max(8,response)
    local b=same and n or math.floor((flast+n+1)/2)
    flast=n;level=n;last=bit
    low=low+math.floor((140*(b-low)+128)/256)
    -- OpenAL mono8 expects unsigned samples, centred on 128.
    out[#out+1]=string.char(math.max(0,math.min(255,low+128)))
   end
  end
  return table.concat(out)
 end
end
function M.new(invoke,address,reader,bytes,clock)
 assert(type(bytes)=='number' and bytes>=0 and bytes%1==0)
 local a={offset=0,left=bytes,paused=false,closed=false,current=nil,queued=nil,startedAt=0,pauseAt=nil,handles={}}
 local decode=M.decoder()
 local function call(m,...)
  local value,e=invoke(address,m,...);if value==nil or value==false then error('audio '..m..': '..tostring(e),0) end;return value
 end
 local function closeHandle(h) if h then pcall(invoke,address,'stop',h.id);pcall(invoke,address,'close',h.id);a.handles[h.id]=nil end end
 local function loadChunk()
  if a.left==0 then return nil end
  local h={id=call('open',0,48000,'mono8'),bytes=0};a.handles[h.id]=h
  local remaining=math.min(2048,a.left)
  while remaining>0 do
   local s,e=reader:read(math.min(512,remaining));if not s or #s==0 then error(e or 'truncated DFPWM audio',0) end
   if #s>remaining then error('audio reader exceeded requested size',0) end
   call('send',h.id,decode(s));h.bytes=h.bytes+#s;remaining=remaining-#s;a.left=a.left-#s
  end
  h.duration=h.bytes/6000
  return h
 end
 function a:start()
  assert(not self.closed and not self.current,'audio already started')
  self.current=loadChunk();self.queued=loadChunk()
  if self.current then call('play',self.current.id);self.startedAt=clock() end
 end
 function a:position()
  if not self.current then return self.offset end
  local now=self.paused and self.pauseAt or clock()
  return self.offset+math.min(self.current.duration,math.max(0,now-self.startedAt))
 end
 function a:pump()
  if self.closed or self.paused or not self.current then return false end
  local playing,e=invoke(address,'isPlaying',self.current.id)
  if playing==nil then error('audio status: '..tostring(e),0) end
  if not playing then
   self.offset=self.offset+self.current.duration;closeHandle(self.current);self.current=self.queued;self.queued=nil
   if self.current then call('play',self.current.id);self.startedAt=clock();self.queued=loadChunk() end
  end
  return self.current~=nil
 end
 function a:setPaused(value)
  if value==self.paused or not self.current then return end
  if value then call('pause',self.current.id);self.pauseAt=clock()
  else call('resume',self.current.id);self.startedAt=self.startedAt+(clock()-self.pauseAt);self.pauseAt=nil end
  self.paused=value
 end
 function a:close()
  if self.closed then return end;self.closed=true
  -- Also releases a partially filled handle if decoding or send failed.
  for _,h in pairs(self.handles) do closeHandle(h) end
  self.current=nil;self.queued=nil;reader:close()
 end
 return a
end
return M
]==])
write('/system/luma/lib/vfs.lua',[==[-- Luma VFS: boot filesystem at / and additional disks under /mnt/<address>.
local M={}
local function normalize(path)
 path=tostring(path or '/'):gsub('\\','/');if path:sub(1,1)~='/' then path='/'..path end
 local parts={}
 for p in path:gmatch('[^/]+') do if p=='.' or p=='' then elseif p=='..' then if #parts>0 then table.remove(parts) end else parts[#parts+1]=p end end
 return '/'..table.concat(parts,'/')
end
local function join(a,b) return normalize((a=='/' and '' or a)..'/'..b) end
function M.new(component,boot,invoke)
 local self={mounts={},byPath={}}
 local function add(path,address,label)
  local m={path=path,address=address,label=label or address:sub(1,8)};self.mounts[#self.mounts+1]=m;self.byPath[path]=m
 end
 add('/',boot,'boot')
 local used={}
 for address in component.list('filesystem') do
  if address~=boot then
   local short=address:sub(1,8);local name=short;local n=2
   while used[name] do name=short..'-'..n;n=n+1 end;used[name]=true
   add('/mnt/'..name,address,(invoke(address,'getLabel') or name))
  end
 end
 table.sort(self.mounts,function(a,b)return a.path<b.path end)
 function self:normalize(path)return normalize(path)end
 function self:resolve(path)
  path=normalize(path)
  if path=='/mnt' then return nil,'virtual' end
  for i=#self.mounts,1,-1 do local m=self.mounts[i]
   if m.path=='/' and path:sub(1,5)=='/mnt/' then return nil,'no mount' end
   if m.path=='/' or path==m.path or path:sub(1,#m.path+1)==m.path..'/' then
    local inner=m.path=='/' and path or path:sub(#m.path+1);if inner=='' then inner='/' end
    return m,inner
   end
  end
  return nil,'no mount'
 end
 function self:stat(path)
  path=normalize(path)
  if path=='/mnt' then return {path=path,name='mnt',dir=true,virtual=true} end
  for _,m in ipairs(self.mounts) do if m.path==path and m.path~='/' then return {path=path,name=path:match('[^/]+$'),dir=true,mount=true,label=m.label} end end
  local m,p=self:resolve(path);if not m then return nil,p end
  local exists,e=invoke(m.address,'exists',p);if not exists then return nil,e or 'not found' end
  local dir=invoke(m.address,'isDirectory',p) and true or false
  return {path=path,name=path=='/' and '/' or path:match('[^/]+$'),dir=dir,size=dir and 0 or tonumber(invoke(m.address,'size',p)) or 0,mountPath=m.path,address=m.address}
 end
 function self:list(path)
  path=normalize(path);local out={}
  if path=='/mnt' then
   for _,m in ipairs(self.mounts) do if m.path~='/' then out[#out+1]={name=m.path:match('[^/]+$')..'/',path=m.path,dir=true,mount=true,label=m.label} end end
   return out
  end
  local m,p=self:resolve(path);if not m then return nil,p end
  local it,e=invoke(m.address,'list',p);if not it then return nil,e end
  local names={}
  if type(it)=='table' then for _,v in ipairs(it) do names[#names+1]=v end else while true do local v=it();if not v then break end;names[#names+1]=v end end
  if path=='/' then
   for i=#names,1,-1 do if names[i]:gsub('/+$','')=='mnt' then table.remove(names,i) end end
   names[#names+1]='mnt/'
  end
  table.sort(names,function(a,b)return a:lower()<b:lower()end)
  for _,name in ipairs(names) do
   if name=='mnt/' and path=='/' then out[#out+1]={name=name,path='/mnt',dir=true,virtual=true}
   else
    local child=join(path,name:gsub('/$',''));local dir=name:sub(-1)=='/' or invoke(m.address,'isDirectory',p..(p=='/' and '' or '/')..name:gsub('/$',''))
    out[#out+1]={name=name,path=child,dir=dir and true or false,size=dir and 0 or tonumber(invoke(m.address,'size',p..(p=='/' and '' or '/')..name)) or 0}
   end
  end
  return out
 end
 function self:read(path,limit)
  local m,p=self:resolve(path);if not m then return nil,p end
  local h,e=invoke(m.address,'open',p,'r');if not h then return nil,e end;local out,n={},0
  while true do local s,er=invoke(m.address,'read',h,8192);if not s then invoke(m.address,'close',h);if er then return nil,er end;break end;n=n+#s;if limit and n>limit then invoke(m.address,'close',h);return nil,'file too large' end;out[#out+1]=s end
  return table.concat(out)
 end
 function self:copy(src,dst,progress)
  local sm,sp=self:resolve(src);local dm,dp=self:resolve(dst);if not sm or not dm then return nil,sp or dp end
  if sm.address==dm.address and sp==dp then return nil,'source and destination are identical' end
  local tmp=dp..'.part';local bak=dp..'.luma-copy-backup'
  if invoke(dm.address,'exists',tmp) or invoke(dm.address,'exists',bak) then return nil,'copy staging file already exists' end
  local input,e=invoke(sm.address,'open',sp,'r');if not input then return nil,e end
  local output,oe=invoke(dm.address,'open',tmp,'w');if not output then invoke(sm.address,'close',input);return nil,oe end
  local total=tonumber(invoke(sm.address,'size',sp)) or 0;local done=0;local ok,why=true
  while true do local s,re=invoke(sm.address,'read',input,8192);if not s then if re then ok,why=nil,re end;break end
   local wrote,we=invoke(dm.address,'write',output,s);if wrote==nil and we then ok,why=nil,we;break end;done=done+#s;if progress then progress(done,total) end
  end
  invoke(sm.address,'close',input);invoke(dm.address,'close',output)
  if not ok then invoke(dm.address,'remove',tmp);return nil,why end
  local had=invoke(dm.address,'exists',dp)
  if had then local saved,se=invoke(dm.address,'rename',dp,bak);if not saved then invoke(dm.address,'remove',tmp);return nil,se end end
  local moved,me=invoke(dm.address,'rename',tmp,dp)
  if not moved then
   if had then invoke(dm.address,'rename',bak,dp) end
   invoke(dm.address,'remove',tmp);return nil,me
  end
  if had then invoke(dm.address,'remove',bak) end
  return true
 end
 function self:trash(path,suffix)
  path=normalize(path);if path=='/' or path=='/mnt' then return nil,'refusing to remove VFS root' end
  local m,p=self:resolve(path);if not m then return nil,p end
  if p=='/' then return nil,'refusing to remove mount root' end
  invoke(m.address,'makeDirectory','/.trash')
  local name=p:match('[^/]+$') or 'item';local target='/.trash/'..name..'-'..tostring(suffix or 'deleted')
  local ok,e=invoke(m.address,'rename',p,target);if not ok then return nil,e end;return true,target
 end
 function self:health()
  local out={}
  for _,m in ipairs(self.mounts) do local total=tonumber(invoke(m.address,'spaceTotal')) or 0;local used=tonumber(invoke(m.address,'spaceUsed')) or 0
   out[#out+1]={path=m.path,address=m.address,label=m.label,total=total,used=used,free=math.max(0,total-used),readOnly=invoke(m.address,'isReadOnly') and true or false}
  end
  return out
 end
 return self
end
return M]==])
write('/system/luma/lib/lupackage.lua',[==[-- LuPackage manifest parser and sandboxed application loader.
local M={}
local function trim(s)return(s:gsub('^%s+',''):gsub('%s+$',''))end
function M.manifest(text)
 local out={permissions={}}
 local allowed={id=true,name=true,entry=true,version=true,permission=true}
 for line in tostring(text or ''):gmatch('[^\r\n]+') do
  line=trim(line)
  if line~='' and line:sub(1,1)~='#' then local k,v=line:match('^([%a_][%w_]*)%s*=%s*(.-)%s*$');if not k then return nil,'invalid manifest line: '..line end;if not allowed[k] then return nil,'unknown manifest field: '..k end;out[k]=v end
 end
 if not out.id or not out.id:match('^[a-z][a-z0-9_.-]*$') then return nil,'invalid app id' end
 if not out.name or out.name=='' then return nil,'missing app name' end
 out.entry=out.entry or 'main.lua';if out.entry:find('..',1,true) or out.entry:sub(1,1)=='/' or out.entry:find('\\',1,true) or out.entry:find('%z') then return nil,'unsafe app entry' end
 for p in tostring(out.permission or ''):gmatch('[^,]+') do out.permissions[trim(p)]=true end
 out.version=out.version or '0.0.0';return out
end
function M.load(source,chunkName,api)
 local function copy(t) if not t then return nil end;local out={};for k,v in pairs(t) do out[k]=v end;return out end
 local env={assert=assert,error=error,ipairs=ipairs,next=next,pairs=pairs,pcall=pcall,select=select,tonumber=tonumber,tostring=tostring,type=type,xpcall=xpcall,math=copy(math),string=copy(string),table=copy(table),utf8=copy(utf8),luma=api}
 env._G=env
 local fn,e=load(source,chunkName or '=app','t',env);if not fn then return nil,e end
 local ok,app=pcall(fn);if not ok then return nil,app end
 local run=type(app)=='function' and app or type(app)=='table' and app.run
 if type(run)~='function' then return nil,'app must return a function or {run=function}' end
 return function()return xpcall(function()return run(api)end,function(er)return debug and debug.traceback(tostring(er),2)or tostring(er)end)end
end
return M]==])
write('/apps/clock/manifest.cfg',[==[id=luma.clock
name=Часы
version=1.0.0
entry=main.lua
permission=screen,input]==])
write('/apps/clock/main.lua',[==[return function(api)
 while true do
  api.clear()
  api.title('ЧАСЫ')
  local seconds=math.floor(api.uptime())
  local h=math.floor(seconds/3600)%24
  local m=math.floor(seconds/60)%60
  local s=seconds%60
  api.center(math.floor(api.height/2),('%02d:%02d:%02d'):format(h,m,s),api.accent)
  api.center(math.floor(api.height/2)+2,'Время работы компьютера · Esc/F1: выход',api.muted)
  local event,key=api.input(1)
  if event=='key_down' and (key==1 or key==59) then return end
 end
end]==])
if not fs.exists("/system/luma/settings.cfg") then write("/system/luma/settings.cfg","eco=1\naccent=mint\n") end
if not fs.exists("/media") then assert(fs.makeDirectory("/media")) end
local ok,err=pcall(function()
 e.set(bios);assert(e.get()==bios,"EEPROM read-back mismatch")
 e.setData(oldData);assert(e.getData()==oldData,"EEPROM data mismatch");pcall(e.setLabel,"LuBIOS 0.3")
end)
if not ok then pcall(e.set,old);pcall(e.setData,oldData);pcall(e.setLabel,oldLabel);error("Flash failed; previous firmware restored: "..tostring(err)) end
print("Luma OS 3 alpha installed; LuBIOS 0.3 flashed and verified.")
print("Copy .lvd files to /media. F2: Recovery; F3: boot disks.")
print("Previous firmware and data: /boot/luma/eeprom-backup.*")
