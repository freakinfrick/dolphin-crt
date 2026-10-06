// crt_scanlines — single-pass CRT look for Dolphin's post-processing slot.
// https://github.com/freakinfrick/dolphin-crt
//
// Runs inside Dolphin's own present pass, so it adds no frame of latency. No temporal
// persistence on purpose: phosphor trails read as input lag.
//
// Algorithm after Timothy Lottes' public-domain "CRT styled scan-line shader" (gaussian
// horizontal filter + gaussian scanline weighting + warp + mask); this is an independent
// rewrite for Dolphin's API. Released CC0 / public domain like its inspiration.
//
// Scanlines follow a virtual line count, not Dolphin's internal resolution (6x IR would
// otherwise give ~3000 invisible lines). The mask defaults low: a fine phosphor mask moires
// into rainbow rings once the image is video-encoded or rescaled (streaming, capture, a TV's
// scaler); scanlines survive that.

/*
[configuration]

[OptionRangeFloat]
GUIName = Virtual scanlines (240 = chunky, 480 = GameCube native)
OptionName = LINES
MinValue = 120.0
MaxValue = 720.0
StepAmount = 8.0
DefaultValue = 480.0

[OptionRangeFloat]
GUIName = Scanline hardness (more negative = thinner, darker gaps)
OptionName = HARD_SCAN
MinValue = -20.0
MaxValue = -2.0
StepAmount = 0.5
DefaultValue = -8.0

[OptionRangeFloat]
GUIName = Horizontal sharpness (more negative = sharper)
OptionName = HARD_PIX
MinValue = -8.0
MaxValue = -1.0
StepAmount = 0.25
DefaultValue = -3.0

[OptionRangeFloat]
GUIName = Curvature X
OptionName = WARP_X
MinValue = 0.0
MaxValue = 0.125
StepAmount = 0.005
DefaultValue = 0.02

[OptionRangeFloat]
GUIName = Curvature Y
OptionName = WARP_Y
MinValue = 0.0
MaxValue = 0.125
StepAmount = 0.005
DefaultValue = 0.03

[OptionRangeFloat]
GUIName = Aperture-grille mask strength (keep low when streaming)
OptionName = MASK_STRENGTH
MinValue = 0.0
MaxValue = 1.0
StepAmount = 0.05
DefaultValue = 0.15

[OptionRangeFloat]
GUIName = Bloom / halation
OptionName = BLOOM
MinValue = 0.0
MaxValue = 1.0
StepAmount = 0.05
DefaultValue = 0.15

[OptionRangeFloat]
GUIName = Corner vignette
OptionName = VIGNETTE
MinValue = 0.0
MaxValue = 1.0
StepAmount = 0.05
DefaultValue = 0.25

[OptionRangeFloat]
GUIName = Brightness boost (scanline gaps darken the image)
OptionName = BRIGHTNESS
MinValue = 0.5
MaxValue = 2.0
StepAmount = 0.05
DefaultValue = 1.2

[/configuration]
*/

float3 ToLinear(float3 c)
{
	return pow(max(c, float3(0.0, 0.0, 0.0)), float3(2.2, 2.2, 2.2));
}

float3 ToGamma(float3 c)
{
	return pow(max(c, float3(0.0, 0.0, 0.0)), float3(1.0 / 2.2, 1.0 / 2.2, 1.0 / 2.2));
}

// Virtual CRT resolution: LINES tall, width keeping the source's pixel aspect.
float2 VirtualRes()
{
	float2 src = GetResolution();
	float lines = GetOption(LINES);
	return float2(floor(src.x * lines / src.y), lines);
}

// Nearest virtual pixel at `pos`, offset by whole virtual pixels; black outside the image.
float3 Fetch(float2 pos, float2 off, float2 res)
{
	pos = (floor(pos * res + off) + 0.5) / res;
	if (pos.x < 0.0 || pos.x > 1.0 || pos.y < 0.0 || pos.y > 1.0)
		return float3(0.0, 0.0, 0.0);
	return ToLinear(SampleLocation(pos).rgb);
}

// Distance from the centre of the current virtual pixel, in virtual pixels.
float2 Dist(float2 pos, float2 res)
{
	pos = pos * res;
	return -((pos - floor(pos)) - float2(0.5, 0.5));
}

float Gaus(float pos, float scale)
{
	return exp2(scale * pos * pos);
}

float3 Horz3(float2 pos, float off, float2 res, float hard)
{
	float3 b = Fetch(pos, float2(-1.0, off), res);
	float3 c = Fetch(pos, float2(0.0, off), res);
	float3 d = Fetch(pos, float2(1.0, off), res);
	float dst = Dist(pos, res).x;
	float wb = Gaus(dst - 1.0, hard);
	float wc = Gaus(dst + 0.0, hard);
	float wd = Gaus(dst + 1.0, hard);
	return (b * wb + c * wc + d * wd) / (wb + wc + wd);
}

float3 Horz5(float2 pos, float off, float2 res, float hard)
{
	float3 a = Fetch(pos, float2(-2.0, off), res);
	float3 b = Fetch(pos, float2(-1.0, off), res);
	float3 c = Fetch(pos, float2(0.0, off), res);
	float3 d = Fetch(pos, float2(1.0, off), res);
	float3 e = Fetch(pos, float2(2.0, off), res);
	float dst = Dist(pos, res).x;
	float wa = Gaus(dst - 2.0, hard);
	float wb = Gaus(dst - 1.0, hard);
	float wc = Gaus(dst + 0.0, hard);
	float wd = Gaus(dst + 1.0, hard);
	float we = Gaus(dst + 2.0, hard);
	return (a * wa + b * wb + c * wc + d * wd + e * we) / (wa + wb + wc + wd + we);
}

float Scan(float2 pos, float off, float2 res, float hard)
{
	return Gaus(Dist(pos, res).y + off, hard);
}

// Three scanlines' worth of light, weighted by distance to each line.
float3 Tri(float2 pos, float2 res)
{
	float hard_pix = GetOption(HARD_PIX);
	float hard_scan = GetOption(HARD_SCAN);
	return Horz3(pos, -1.0, res, hard_pix) * Scan(pos, -1.0, res, hard_scan) +
	       Horz3(pos, 0.0, res, hard_pix) * Scan(pos, 0.0, res, hard_scan) +
	       Horz3(pos, 1.0, res, hard_pix) * Scan(pos, 1.0, res, hard_scan);
}

// Wide, soft version of Tri for the glow around bright areas.
float3 Bloom(float2 pos, float2 res)
{
	const float hard_pix = -1.5;
	const float hard_scan = -2.0;
	return Horz5(pos, -2.0, res, hard_pix) * Scan(pos, -2.0, res, hard_scan) +
	       Horz5(pos, -1.0, res, hard_pix) * Scan(pos, -1.0, res, hard_scan) +
	       Horz5(pos, 0.0, res, hard_pix) * Scan(pos, 0.0, res, hard_scan) +
	       Horz5(pos, 1.0, res, hard_pix) * Scan(pos, 1.0, res, hard_scan) +
	       Horz5(pos, 2.0, res, hard_pix) * Scan(pos, 2.0, res, hard_scan);
}

float2 Warp(float2 pos)
{
	pos = pos * 2.0 - 1.0;
	pos *= float2(1.0 + (pos.y * pos.y) * GetOption(WARP_X), 1.0 + (pos.x * pos.x) * GetOption(WARP_Y));
	return pos * 0.5 + 0.5;
}

// Aperture grille in output pixels (vertical RGB stripes, 3 px per triad), faded by strength.
float3 Mask(float2 frag)
{
	float strength = GetOption(MASK_STRENGTH);
	float x = fract(frag.x / 3.0);
	float3 m = float3(0.5, 0.5, 0.5);
	if (x < 1.0 / 3.0)
		m.r = 1.5;
	else if (x < 2.0 / 3.0)
		m.g = 1.5;
	else
		m.b = 1.5;
	return lerp(float3(1.0, 1.0, 1.0), m, strength);
}

void main()
{
	float2 pos = Warp(GetCoordinates());
	if (pos.x < 0.0 || pos.x > 1.0 || pos.y < 0.0 || pos.y > 1.0)
	{
		SetOutput(float4(0.0, 0.0, 0.0, 1.0));
		return;
	}

	float2 res = VirtualRes();
	float3 color = Tri(pos, res);
	float bloom = GetOption(BLOOM);
	if (bloom > 0.0)
		color += Bloom(pos, res) * bloom * 0.25;

	color *= Mask(GetCoordinates() * GetWindowResolution());
	color *= GetOption(BRIGHTNESS);

	float vig = GetOption(VIGNETTE);
	if (vig > 0.0)
		color *= pow(clamp(16.0 * pos.x * pos.y * (1.0 - pos.x) * (1.0 - pos.y), 0.0, 1.0), vig * 0.5);

	SetOutput(float4(ToGamma(color), 1.0));
}
