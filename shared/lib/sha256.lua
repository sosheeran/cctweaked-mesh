-- shared/lib/sha256.lua
-- SHA-256 for CC: Tweaked (Lua 5.1) - pure Lua, no dependencies

local MOD  = 2^32
local MODM = MOD - 1

local function memoize(f)
  local t = setmetatable({}, {
    __index = function(t,k)
      local v = f(k); t[k] = v; return v
    end
  })
  return t
end

local function make_bitop(t, m)
  local function op(a, b)
    local res, p = 0, 1
    while a ~= 0 and b ~= 0 do
      local am, bm = a % m, b % m
      res = res + t[am * m + bm] * p
      a = (a - am) / m
      b = (b - bm) / m
      p = p * m
    end
    return res + (a + b) * p
  end
  local op2 = memoize(function(a)
    return memoize(function(b) return op(a, b) end)
  end)
  return function(a, b) return op2[a][b] end
end

local bxor1 = make_bitop({[0]=0,[1]=1,[4]=1,[5]=0}, 4)

local function bxor(a, b, c, ...)
  local z
  if b then
    a = a % MOD; b = b % MOD; z = 0
    local i = 1
    while true do
      if a == 0 then z = z + b; break end
      if b == 0 then z = z + a; break end
      local x = a % 2
      z = z + (x ~= b % 2 and i or 0)
      a = (a - x) / 2
      b = (b - b % 2) / 2
      i = i * 2
    end
    if c then z = bxor(z, c, ...) end
  end
  return z
end

local function band(a, b)
  local res, p = 0, 1
  while a ~= 0 and b ~= 0 do
    local am, bm = a % 2, b % 2
    if am == 1 and bm == 1 then res = res + p end
    a = (a - am) / 2; b = (b - bm) / 2; p = p * 2
  end
  return res
end

local function bnot(a) return MODM - a % MOD end
local function rshift(a, d) return math.floor(a % MOD / 2^d) end
local function rrotate(a, d)
  a = a % MOD
  return math.floor(a / 2^d) + (a % 2^d) * 2^(32 - d)
end

local K = {
  0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,
  0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
  0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,
  0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
  0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,
  0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
  0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,
  0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
  0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,
  0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
  0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,
  0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
  0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,
  0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
  0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,
  0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2,
}

local function num2s(l, n)
  local s = ""
  for i = 1, n do
    local r = l % 256; s = string.char(r) .. s; l = (l - r) / 256
  end
  return s
end

local function s232num(s, i)
  local n = 0
  for j = i, i + 3 do n = n * 256 + string.byte(s, j) end
  return n
end

local function preproc(msg, len)
  local extra = 64 - ((len + 9) % 64)
  msg = msg .. "\128" .. string.rep("\0", extra) .. num2s(8 * len, 8)
  assert(#msg % 64 == 0)
  return msg
end

local function initH()
  return {
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
  }
end

local function digestblock(msg, i, H)
  local w = {}
  for j = 1, 16 do w[j] = s232num(msg, i + (j-1) * 4) end
  for j = 17, 64 do
    local v  = w[j-2]
    local s1 = bxor(rrotate(v,17), rrotate(v,19), rshift(v,10))
    v        = w[j-15]
    local s0 = bxor(rrotate(v,7),  rrotate(v,18), rshift(v,3))
    w[j]     = (w[j-16] + s0 + w[j-7] + s1) % MOD
  end
  local a,b,c,d,e,f,g,h =
    H[1],H[2],H[3],H[4],H[5],H[6],H[7],H[8]
  for j = 1, 64 do
    local s1  = bxor(rrotate(e,6),  rrotate(e,11), rrotate(e,25))
    local ch  = bxor(band(e,f), band(bnot(e),g))
    local t1  = (h + s1 + ch + K[j] + w[j]) % MOD
    local s0  = bxor(rrotate(a,2),  rrotate(a,13), rrotate(a,22))
    local maj = bxor(band(a,b), band(a,c), band(b,c))
    local t2  = (s0 + maj) % MOD
    h,g,f,e,d,c,b,a =
      g, f, e, (d+t1)%MOD, c, b, a, (t1+t2)%MOD
  end
  H[1]=(H[1]+a)%MOD; H[2]=(H[2]+b)%MOD
  H[3]=(H[3]+c)%MOD; H[4]=(H[4]+d)%MOD
  H[5]=(H[5]+e)%MOD; H[6]=(H[6]+f)%MOD
  H[7]=(H[7]+g)%MOD; H[8]=(H[8]+h)%MOD
end

local function sha256(msg)
  msg    = preproc(msg, #msg)
  local H = initH()
  for i = 1, #msg, 64 do digestblock(msg, i, H) end
  local hex = ""
  for i = 1, 8 do hex = hex .. string.format("%08x", H[i]) end
  return hex
end

return sha256
