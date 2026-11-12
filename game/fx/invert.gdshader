shader_type canvas_item;
// 负片：把它下面已经画好的画面反色（终局「负片」段）。红心画在它后面，所以红心不被反色。
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float amount : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	COLOR = vec4(mix(c, vec3(1.0) - c, amount), 1.0);
}
