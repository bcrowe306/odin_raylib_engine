package engine

import "core:testing"

@(test)
test_version_compare :: proc(t: ^testing.T) {
	testing.expect_value(t, Version_Compare("1.2.3", "1.2.3"), 0)
	testing.expect_value(t, Version_Compare("1.2.10", "1.2.9"), 1)
	testing.expect_value(t, Version_Compare("1.3.0", "1.10.0"), -1)
	testing.expect_value(t, Version_Compare("2.0.0", "1.99.99"), 1)
	testing.expect_value(t, Version_Compare("v1.0.0", "1.0.0"), 0)
	// A pre-release comes before its release.
	testing.expect_value(t, Version_Compare("1.0.0-beta.1", "1.0.0"), -1)
	testing.expect_value(t, Version_Compare("1.0.0", "1.0.0-rc.1"), 1)
	testing.expect_value(t, Version_Compare("1.0.0-alpha", "1.0.0-beta"), -1)
	testing.expect(t, Version_IsDev("0.0.0-dev"))
	testing.expect(t, Version_IsDev("0.0.0-ci.12"))
	testing.expect(t, Version_IsDev(""))
	testing.expect(t, !Version_IsDev("0.1.0"))
}
