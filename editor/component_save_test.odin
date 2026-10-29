package editor

import "core:os"
import "core:path/filepath"
import "core:testing"

// #73: component file names are cleaned for every platform, and saving
// never replaces an existing component (a free name: Enemy_2, Enemy_3...).
@(test)
test_component_file_names :: proc(t: ^testing.T) {
	testing.expect_value(t, Component_SafeName("Enemy"), "Enemy")
	testing.expect_value(t, Component_SafeName(`a/b\c:d*e?f"g<h>i|j`), "a_b_c_d_e_f_g_h_i_j")
	testing.expect_value(t, Component_SafeName("  ..Boss.  "), "Boss")
	testing.expect_value(t, Component_SafeName("///"), "___")
	testing.expect_value(t, Component_SafeName(""), "Component")

	dir :: "test_component_save"
	defer os.remove_all(dir)
	comps, _ := filepath.join({dir, "components"}, context.temp_allocator)
	_ = os.make_directory_all(comps)
	state: EditorState
	state.projectPath = dir
	testing.expect_value(t, Component_FreePath(&state, "Enemy"), "components/Enemy.component.json")
	f1, _ := filepath.join({comps, "Enemy.component.json"}, context.temp_allocator)
	_ = os.write_entire_file(f1, transmute([]u8)string("{}"))
	testing.expect_value(t, Component_FreePath(&state, "Enemy"), "components/Enemy_2.component.json")
	f2, _ := filepath.join({comps, "Enemy_2.component.json"}, context.temp_allocator)
	_ = os.write_entire_file(f2, transmute([]u8)string("{}"))
	testing.expect_value(t, Component_FreePath(&state, "Enemy"), "components/Enemy_3.component.json")
}
