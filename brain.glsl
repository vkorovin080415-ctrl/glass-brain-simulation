
#define MAX_STEPS 160
#define MAX_DIST 5.0
#define SURF_DIST 0.0004
#define NORMAL_EPS 0.0008

#define AA 2

mat2 rot2D(float a) {
float s = sin(a), c = cos(a);
return mat2(c, -s, s, c);
}

float smin(float a, float b, float k) {
float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
return mix(b, a, h) - k * h * (1.0 - h);
}

float sdEllipsoid(vec3 p, vec3 r) {
float k0 = length(p / r);
float k1 = length(p / (r * r));
return k0 * (k0 - 1.0) / k1;
}

float hash3D(vec3 p) {
p = fract(p * vec3(443.897, 441.423, 437.195));
p += dot(p, p.yzx + 19.19);
return fract((p.x + p.y) * p.z);
}

float noise3D(vec3 p) {
vec3 i = floor(p);
vec3 f = fract(p);
vec3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);

return mix(
mix(mix(hash3D(i + vec3(0,0,0)), hash3D(i + vec3(1,0,0)), u.x),
mix(hash3D(i + vec3(0,1,0)), hash3D(i + vec3(1,1,0)), u.x), u.y),
mix(mix(hash3D(i + vec3(0,0,1)), hash3D(i + vec3(1,0,1)), u.x),
mix(hash3D(i + vec3(0,1,1)), hash3D(i + vec3(1,1,1)), u.x), u.y), u.z);
}

// Ridged noise for deep cortical sulci/gyri silhouette carving
float getCorticalFolds(vec3 p) {
vec3 q = p * 14.0;
float n1 = noise3D(q);
float n2 = noise3D(q * 2.1 + vec3(1.7));
float gyri = abs(n1 * 2.0 - 1.0) * 0.7 + abs(n2 * 2.0 - 1.0) * 0.3;
return smoothstep(0.15, 0.85, gyri);
}

// --- RE-ARCHITECTED ANATOMICAL BRAIN GEOMETRY ---
float sdfBrainGeometry(vec3 p) {
vec3 q = p;

// 1. ANATOMICAL DOMAIN WARPING (Removes the lightbulb/sphere look)
// Frontal Lobe: Push forward (+Z) and flatten base
q.z += smoothstep(-0.05, 0.15, q.y) * 0.035;
// Temporal Lobe: Drop downwards (-Y) and widen on sides (+X) at the middle base
float temporalMask = smoothstep(0.1, -0.15, q.z) * smoothstep(0.1, -0.1, q.y);
q.y -= temporalMask * 0.04;
q.x += sign(q.x) * temporalMask * 0.025;

// Occipital Lobe: Taper downwards towards the back (-Z)
q.y += smoothstep(-0.05, 0.2, -q.z) * 0.02;

// Smooth Dual Hemisphere Splitting
vec3 symP = q;
symP.x = sqrt(q.x * q.x + 0.0001); // C1-continuous smooth absolute value

// 2. PRIMARY LOBE PRIMITIVES
// Cerebrum (Main Lobes) - Elongated & flattened profile
vec3 pCerebrum = symP - vec3(0.05, 0.04, 0.01);
float cerebrum = sdEllipsoid(pCerebrum, vec3(0.16, 0.16, 0.26));

// Temporal Lobe Hook Addition
vec3 pTemporal = symP - vec3(0.11, -0.05, 0.02);
float temporalLobe = sdEllipsoid(pTemporal, vec3(0.07, 0.06, 0.11));
cerebrum = smin(cerebrum, temporalLobe, 0.08);

// Cerebellum (Back/Bottom separate structure)
vec3 pCerebellum = symP - vec3(0.04, -0.12, -0.14);
float cerebellum = sdEllipsoid(pCerebellum, vec3(0.11, 0.065, 0.09));

// Brainstem (Narrowing descending stalk)
vec3 pStem = p - vec3(0.0, -0.22, -0.04);
float stemRadius = mix(0.032, 0.018, clamp((-p.y - 0.12) / 0.16, 0.0, 1.0));
float stem = length(pStem.xz) - stemRadius;
stem = max(stem, abs(pStem.y) - 0.09);

// Combine main anatomical structures
float d = smin(cerebrum, cerebellum, 0.09);
d = smin(d, stem, 0.06);

// 3. LONGITUDINAL FISSURE (Deep Center Seam)
float smoothX = sqrt(p.x * p.x + 0.0008);
float fissure = exp(-smoothX * 32.0) * smoothstep(-0.08, 0.22, p.y) * 0.004;
d += fissure;

// 4. CORTICAL SURFACE GYRI/SULCI DISPLACEMENT
// Directly carves the silhouette outer boundary
float folds = getCorticalFolds(symP);
float foldMask = smoothstep(-0.16, 0.05, p.y); // Fade out near stem
d += (folds * 0.007 - 0.0035) * foldMask;

return d;
}

vec3 calcNormal(vec3 p) {
vec2 e = vec2(1.0, -1.0) * NORMAL_EPS;
return normalize(
e.xyy * sdfBrainGeometry(p + e.xyy) +
e.yyx * sdfBrainGeometry(p + e.yyx) +
e.yxy * sdfBrainGeometry(p + e.yxy) +
e.xxx * sdfBrainGeometry(p + e.xxx)
);
}

// --- DTI FIBER GENERATOR (MULTIPLE DISTINCT ACTION POTENTIAL CLASSES) ---
vec3 getInternalDTIFibers(vec3 p, float time) {
vec3 corePos = vec3(0.0, -0.02, 0.0);
vec3 dirFromCore = p - corePos;
float distFromCore = length(dirFromCore);

// 1. Organic Fiber Domain Warping
vec3 warp1 = vec3(
noise3D(p * 10.0 + vec3(0.0, time * 0.05, 0.0)),
noise3D(p * 10.0 + vec3(17.3, 0.0, time * 0.05)),
noise3D(p * 10.0 + vec3(0.0, 31.4, time * 0.05))
);
vec3 q = p * 28.0 + warp1 * 4.5;

vec3 warp2 = vec3(
noise3D(q * 0.4 + vec3(5.2)),
noise3D(q * 0.4 + vec3(13.1)),
noise3D(q * 0.4 + vec3(2.7))
);
q += warp2 * 2.0;

// Organic Strand Distance Field
float strandNoise1 = noise3D(q);
float strandNoise2 = noise3D(q * 2.3 + vec3(11.4));
float strandDist = abs(strandNoise1 - strandNoise2);
float strandMask = exp(-strandDist * 16.0);
float coreMask = smoothstep(0.34, 0.03, distFromCore);

// 2. Base Fiber Color Palette
vec3 coreHot = vec3(1.0, 0.85, 0.3);
vec3 midRed = vec3(0.9, 0.25, 0.08);
vec3 outerPink = vec3(0.6, 0.1, 0.35);

vec3 fiberColor = mix(outerPink, midRed, smoothstep(0.25, 0.10, distFromCore));
fiberColor = mix(fiberColor, coreHot, smoothstep(0.12, 0.02, distFromCore));

// 3. MULTI-TYPE NEURONAL SPIKE GENERATOR
vec3 strandID = floor(q * 0.35);
float strandSeed = hash3D(strandID);
float strandSeed2 = hash3D(strandID + vec3(4.1, 8.2, 1.3));
float strandSeed3 = hash3D(strandID + vec3(9.7, 2.5, 6.1)); // Spike Type Allocator

// SPIKE CLASSIFICATION (Determined per strand)
float travelSpeed = 0.4;
float spikeCycle = 4.0 + strandSeed2 * 5.0;
float leadFalloff = 120.0; // Leading edge sharpness
float trailDecay = 35.0; // Trailing decay length
float thickness = 16.0; // Spatial fiber width multiplier
vec3 spikeColor = vec3(1.2, 1.1, 0.9);
float brightness = 8.0;

if (strandSeed3 < 0.40) {
// --- CLASS 0: Rapid Micro-Spike (Fast, localized, high frequency) ---
travelSpeed = 0.45 + strandSeed * 0.4;
spikeCycle = 3.0 + strandSeed2 * 3.0;
leadFalloff = 140.0;
trailDecay = 40.0;
thickness = 16.0;
spikeColor = vec3(1.2, 1.1, 0.9);
brightness = 7.0;
}
else if (strandSeed3 < 0.70) {
// --- CLASS 1: Slow Creep Wave (Deep, slow propagation, warm glow) ---
travelSpeed = 0.12 + strandSeed * 0.15; // ~3x slower travel
spikeCycle = 6.0 + strandSeed2 * 6.0; // Infrequent cycles
leadFalloff = 45.0; // Soft leading edge
trailDecay = 12.0; // Long lingering body
thickness = 12.0;
spikeColor = vec3(1.0, 0.75, 0.3); // Deeper amber tint
brightness = 4.5;
}
else {
// --- CLASS 2: Long & Thick Surge (Heavy intensity, wide radius, extended tail) ---
travelSpeed = 0.3 + strandSeed * 0.3;
spikeCycle = 5.0 + strandSeed2 * 4.0;
leadFalloff = 35.0; // Wide, thick wavefront
trailDecay = 8.0; // Extremely long tail
thickness = 7.0; // Lower multiplier = thicker fiber radius
spikeColor = vec3(1.4, 1.3, 1.1); // Blinding white/gold core
brightness = 14.0;
}

// Phase & Timing Engine
float localTime = time + strandSeed * 100.0;
float timeSinceFire = mod(localTime, spikeCycle);
float frontPos = timeSinceFire * travelSpeed;
float distToSpike = distFromCore - frontPos;

// Asymmetric Envelope Calculation
float spike = 0.0;
if (distToSpike <= 0.0) {
spike = exp(distToSpike * trailDecay);
} else {
spike = exp(-distToSpike * leadFalloff);
}

// Dynamic Strand Thickness Adjuster for Class 2
float localStrandMask = exp(-strandDist * thickness);

// Rarity Gate: ~12% overall activation density
float rarityGate = step(0.88, strandSeed);

vec3 actionPotential = spikeColor * pow(spike, 1.8) * brightness * rarityGate;

// Final Composite
return (fiberColor * strandMask * 1.2 + actionPotential * localStrandMask) * coreMask;
}

vec3 renderRay(vec2 uv, vec2 mouse) {
float angle = iTime * 0.12;
if (mouse.y > 0.0) angle = (mouse.x / iResolution.x) * 6.28;

vec3 ro = vec3(0.0, 0.05, -1.6);
vec3 ta = vec3(0.0, -0.02, 0.0);
ro.xz *= rot2D(angle + 1.2);

vec3 ww = normalize(ta - ro);
vec3 uu = normalize(cross(ww, vec3(0.0, 1.0, 0.0)));
vec3 vv = normalize(cross(uu, ww));
vec3 rd = normalize(uv.x * uu + uv.y * vv + 1.8 * ww);

vec3 finalColor = vec3(0.0);
vec3 glassSpecColor = vec3(1.0, 0.9, 0.5);
vec3 lightPos = vec3(1.2, 1.5, -1.2);

float t1 = 0.0;
bool hitFront = false;

for (int i = 0; i < MAX_STEPS; i++) {
vec3 p = ro + rd * t1;
float d = sdfBrainGeometry(p);
if (d < SURF_DIST) {
hitFront = true;
break;
}
t1 += d * 0.5;
if (t1 > MAX_DIST) break;
}

if (hitFront) {
vec3 pFront = ro + rd * t1;
vec3 nFront = calcNormal(pFront);
vec3 lightDir = normalize(lightPos - pFront);
vec3 viewDir = -rd;

float ior = 1.52;
float R0 = pow((1.0 - ior) / (1.0 + ior), 2.0);
float fresnel = R0 + (1.0 - R0) * pow(1.0 - max(dot(nFront, viewDir), 0.0), 5.0);

vec3 halfVec = normalize(lightDir + viewDir);
float spec = pow(max(dot(nFront, halfVec), 0.0), 2048.0);
vec3 specularReflection = glassSpecColor * spec * 8.0;

vec3 edgeRim = vec3(0.95, 0.8, 0.3) * pow(fresnel, 4.0) * 10.;

float tInternal = 0.005;
vec3 fiberEmissive = vec3(0.0);

for (int i = 0; i < 64; i++) {
vec3 p = pFront + rd * tInternal;
float d = sdfBrainGeometry(p);

if (d < 0.0) {
fiberEmissive += getInternalDTIFibers(p, iTime) * 0.035;
} else {
break;
}
tInternal += 0.007;
}

finalColor = fiberEmissive + edgeRim + specularReflection;
}

finalColor = vec3(1.0) - exp(-finalColor * 1.8);
finalColor = pow(finalColor, vec3(0.90));

return finalColor;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
vec3 colAcc = vec3(0.0);
#if AA > 1
for (int m = 0; m < AA; m++) {
for (int n = 0; n < AA; n++) {
vec2 offset = (vec2(float(m), float(n)) / float(AA) - 0.5);
vec2 uv = ((fragCoord + offset) - 0.5 * iResolution.xy) / iResolution.y;
colAcc += renderRay(uv, vec2(iMouse.x, iMouse.z));
}
}
colAcc /= float(AA * AA);
#else
vec2 uv = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
colAcc = renderRay(uv, vec2(iMouse.x, iMouse.z));
#endif

fragColor = vec4(colAcc, 1.0);
} 
