ac.setMIPs(9)

local shader = [[     

  const static float3 POISSON_DISC_16[16] = {
    float3(0.8954767f, -0.1575644f, 0.9092332f),
    float3(0.4352259f, -0.4984821f, 0.6617447f),
    float3(0.7695779f, 0.3616731f, 0.850328f),
    float3(0.1323851f, 0.0497573f, 0.141427f),
    float3(0.2105618f, 0.9109722f, 0.9349902f),
    float3(0.2277734f, 0.4944786f, 0.544417f),
    float3(-0.380273f, 0.1147139f, 0.3971987f),
    float3(-0.1111894f, -0.2835931f, 0.3046114f),
    float3(-0.2282531f, 0.5713289f, 0.6152368f),
    float3(-0.5346423f, -0.2667225f, 0.5974808f),
    float3(-0.5894181f, -0.762647f, 0.9638693f),
    float3(-0.2105553f, -0.9640824f, 0.9868071f),
    float3(-0.6383594f, 0.4755866f, 0.7960436f),
    float3(-0.9285333f, 0.1501847f, 0.9406006f),
    float3(0.3938299f, -0.9144654f, 0.995665f),
    float3(-0.9361477f, -0.3214122f, 0.989787f)
  };

  float4 readBlurred(float2 uv, float2 radius, float level){
    float4 r = 0;
    for (int i = 0; i < 16; ++i){
      float4 s = txInput.SampleLevel(samLinearClamp, uv + POISSON_DISC_16[i] * radius, level);
      r += float4(s.rgb, 1) * (dot(s.rgb, 1) + 0.1);
    }
    return r / r.w;
  }

  float luminance(float3 rgb) {
    return dot(rgb, float3(0.2125, 0.7154, 0.0721));
  }  

  float4 sampleNoise(float2 uv, bool fixUv = false){
    if (fixUv){
      float textureResolution = 32;
      uv = uv * textureResolution + 0.5;
      float2 i = floor(uv);
      float2 f = frac(uv);
      uv = i + f * f * (3 - 2 * f);
      uv = (uv - 0.5) / textureResolution;
    }
    return txNoise.SampleLevel(samLinearSimple, uv, 0);
  }

  float4 main(PS_IN pin) {
    float2 uv = pin.Tex + gTexOffset + pin.Tex.yx * float2(gAspectRatioInv, 1) * float2(gTexSkew, -gTexSkew) + float2(-0.5, 0.5) * gTexSkew;
    uv.y += gOffset;

    float edge = pow(length(pin.Tex * 2 - 1) / 1.5, 1);

    float4 noise = txNoise.SampleLevel(samLinearSimple, pin.Tex + gNoiseOffset, 0);
    noise = noise * 0.7 + 0.3 * txNoise.SampleLevel(samLinearSimple, pin.Tex * 3.71 + gNoiseOffset, 0);

    float4 col;
    if (gBlurLevel.x > 0.000001){
      col = readBlurred(uv, gBlurLevel, gBaseLevel + edge * 2);
    } else {
      col = txInput.SampleLevel(samLinearBorder0, uv, gBaseLevel + edge * 2);
    }
    // col += pow(readBlurred(uv, float2(0.05, 0.2), 6.5), 4) * 0.4;
    col *= 0.8;
    col += pow(readBlurred(uv, float2(0.05, 0.2), 7.5), 4) * 4;

    col.rgb = luminance(col.rgb);
    col.rgb = smoothstep(0, 1, col.rgb);

    col.rgb = lerp(col.rgb, 0.2, edge);
    col.rgb += gFlicker;

    col.rgb *= float3(1.06, 0.92 + 0.04 * noise.w, 0.8 + 0.08 * noise.z);

    float stripe = saturate((gStripeWidth * lerp(-0.2, 1, noise.x) - abs(pin.Tex.x - gStripePosition)) * 1000);
    if (stripe){
      float4 noise = txNoise.SampleLevel(samLinearSimple, pin.Tex * 0.1 + gScratch, 0);
      col.rgb += gStripeColor * lerp(0.5, 1, noise.y) * stripe * lerp(noise.w, 0, abs(pin.Tex.y * lerp(2, 4, gNoiseOffset.x) - gNoiseOffset.y * 2));
    }

    float spot = smoothstep(0, 1, saturate(6 * (gSpotSize - length((pin.Tex + (noise.zw - 0.5) * 0.1 - gSpot) * float2(1, gSpotHeight)))));
    if (spot){
      col.rgb += spot * gSpotColor;
    }

    if (gFlash){
      col.rgb += gFlash * smoothstep(0, 1, saturate(txNoise.SampleLevel(samLinearSimple, pin.Tex * 0.0397 + gFlashNoiseOffset, 0).y * 4 - 2 + gFlash));
    }

    {
      float4 noise = txNoise.SampleLevel(samLinearSimple, pin.Tex * 0.3 * float2(1, gAspectRatioInv) + gScratch, 0);
      float4 scratch = sampleNoise(pin.Tex * 0.1 * float2(1, gAspectRatioInv) + gScratch, true);
      if (abs(scratch.y - 0.5) < fwidth(scratch.y) * noise.y){
        col.rgb -= saturate(noise.x * 24.5 - gScratchChance);
      }
    }

    {
     // float4 noise = txNoise.SampleLevel(samLinearSimple, pin.Tex * 0.3 * float2(1, gAspectRatioInv) + gScratch, 0);
      float4 scratch = sampleNoise(pin.Tex * 0.4 * float2(1, gAspectRatioInv) + noise.zw * 0.04 + gScratch, true)
        - sampleNoise(pin.Tex * 9.1 * float2(1, gAspectRatioInv) + gScratch, false) * 0.3;
      if (scratch.r > 0.9){
        col.rgb += saturate(noise.x * 24 - gScratchChance);
      }
    }

    {
      float4 noise = txNoise.SampleLevel(samLinearSimple, pin.Tex * 1.3 * float2(1, gAspectRatioInv) + gScratch, 0);
      noise = noise * 0.5 + 0.5 * txNoise.SampleLevel(samLinearSimple, pin.Tex * 3.7 * float2(1, gAspectRatioInv) + gScratch, 0);
      noise = noise * 0.5 + 0.5 * txNoise.SampleLevel(samLinearSimple, pin.Tex * 37.1 * float2(1, gAspectRatioInv) + gScratch, 0);
      noise = noise * 0.5 + 0.5 * txNoise.SampleLevel(samLinearSimple, pin.Tex * 379.1 * float2(1, gAspectRatioInv) + gScratch, 0);
      if (noise.r > 0.9){
        col.rgb += 1;
      }
    }

    {
      float4 noiseL = txNoise.SampleLevel(samLinearSimple, pin.Tex * 0.0371 * float2(1, gAspectRatioInv) + gScratch, 0);
      float4 scratch = sampleNoise(pin.Tex * 0.25 * float2(1, gAspectRatioInv) + noise.xy * 0.01 + gScratch, true)
      - sampleNoise(pin.Tex * 9.1 * float2(1, gAspectRatioInv) + gScratch, false) * 0.05
      - sampleNoise(pin.Tex * 39.1 * float2(1, gAspectRatioInv) + gScratch, false) * 0.05;
      scratch.r *= saturate(noiseL.y * 4 - gBlobChance);
      if (scratch.r > 0.8){
        col.rgb -= min(saturate(scratch.r * 5 - 4) * 0.4, 0.2);
      }
    }

    return col;
  }
]]

local offset = 0
local offsetSmooth = 0
local flash = 0
local flashNoiseOffset = vec2(0.5, 0.5)
local texOffset = vec2()
local texSkew = 0
local baseLevel = 0
local blurLevel = 0
local blurLevelSmooth = 0

function script.update(dt)
  local sim = ac.getSim()
  local paused = sim.isPaused or sim.replayPlaybackRate == 0
  local aspectRatio = ui.windowWidth() / ui.windowHeight()

  offset = math.applyLag(offset, 0, 0.95, dt)
  if math.random() > 0.95 + math.sin(sim.time / 1e3) * math.sin(sim.time / 1.71e3) * 0.04 then
    offset = offset + (math.random() - 0.5) * 0.01
  end
  offsetSmooth = math.applyLag(offsetSmooth, offset, 0.5, dt)

  if math.random() > 0.995 then
    flash = math.random() > 0.3 and math.random() or -math.random() / 2
    flashNoiseOffset.x, flashNoiseOffset.y = math.random(), math.random()
  else
    flash = math.applyLag(flash, 0, 0.6, dt)
  end

  if math.random() > 0.95 then
    texOffset = vec2(math.random(), math.random()) * 0.0012
    texSkew = math.random() * 0.005
  end

  if math.random() > 0.99 then
    baseLevel = math.random() ^ 2 * 0.8
  end

  local r = math.random()
  if r > 0.98 - blurLevelSmooth * 0.04 then
    blurLevel = r < 0.981 and 1 + math.random() or 0
  end
  blurLevelSmooth = math.applyLag(blurLevelSmooth, blurLevel, 0.8, dt)

  ui.renderShader({
    p1 = vec2(),
    p2 = ui.windowSize(),
    blendMode = render.BlendMode.Opaque,
    textures = {
      txInput = 'dynamic::screen',
      txNoise = 'dynamic::noise'
    },
    values = {
      gBaseLevel = baseLevel + blurLevelSmooth,
      gBlurLevel = vec2(1, aspectRatio):scale(blurLevelSmooth * 0.002),
      gAspectRatioInv = 1 / aspectRatio,
      gTimeS = sim.time / 1e3,
      gPaused = paused,
      gOffset = offsetSmooth,
      gFlicker = (math.random() - 0.5) ^ 7,
      gTexOffset = texOffset,
      gTexSkew = texSkew,

      gStripeColor = math.random() > 0.1 and 1 or -1,
      gStripeWidth = math.random() * 0.003 + 0.002,
      gStripePosition = math.random() > 0.95 and math.random() or -1,

      gSpot = math.random() > 0.995 and vec2(math.random(), math.random()) or vec2(-1, -1),
      gSpotColor = math.random() > 0.1 and 1 or -1,
      gSpotSize = 0.05 + math.random() ^ 2 * 0.15,
      gSpotHeight = 0.5 + math.random(),

      gFlash = flash,
      gFlashNoiseOffset = flashNoiseOffset,

      gScratch = vec2(math.random(), math.random()),
      gScratchChance = 24 - math.random() ^ 2 * 5,
      gBlobChance = 4 - math.random() ^ 2 * 2,

      gNoiseOffset = vec2(math.random(), math.random()),
    },
    shader = shader
  })
end
