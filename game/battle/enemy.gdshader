shader_type canvas_item;
// 她的立绘：白闪、像素化、剪影（染成一种颜色）、负片、按行错位故障。全部默认不起作用。

uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform float pixel = 0.0;            // 像素块大小（贴图像素）；< 1.5 不处理
uniform float sil : hint_range(0.0, 1.0) = 0.0;
uniform vec4 sil_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float neg : hint_range(0.0, 1.0) = 0.0;
uniform float glitch : hint_range(0.0, 1.0) = 0.0;
uniform float seed = 0.0;

float hash(float n) { return fract(sin(n * 12.9898 + seed * 78.233) * 43758.5453); }

void fragment() {
	vec2 uv = UV;
	vec2 ts = 1.0 / TEXTURE_PIXEL_SIZE;
	if (glitch > 0.0) {
		float row = floor(uv.y * 64.0);
		float h = hash(row);
		if (h < glitch * 0.45) {
			uv.x += (hash(row + 17.0) - 0.5) * 0.18 * glitch;
		}
	}
	vec4 c;
	if (pixel > 1.5) {
		vec2 cell = (floor(uv * ts / pixel) + 0.5) * pixel / ts;
		c = textureLod(TEXTURE, cell, log2(pixel));
	} else {
		c = texture(TEXTURE, uv);
	}
	c.rgb = mix(c.rgb, sil_color.rgb, sil);
	c.rgb = mix(c.rgb, vec3(1.0) - c.rgb, neg);
	c.rgb = mix(c.rgb, vec3(1.0), flash);
	COLOR = c * COLOR;
}
