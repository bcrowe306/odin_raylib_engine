package main

import "core:strings"
import "core:fmt"


StartState :: enum {
	Root,
	Relative,
	Parent,
}

main :: proc() {

	names := []string {
		"Brandon",
		"Crowe",
		"Is",
		"A",
		"Boss",
	}
	path := "./Brandon/Crowe/Is/A/Boss"

	res, err := strings.split(path, "/")
	if len(res) <= 0 || err != nil {
		fmt.println("Error splitting path: ", err)
		return
	}

	start :StartState
	startIndex := 0
	if res[0] == "" {
		start = .Root
		startIndex = 1
	}
	else if res[0] == "." {
		start = .Relative
		startIndex = 1
	}
	else if res[0] == ".." {
		start = .Parent
		startIndex = 1
	}
	else {
		start = .Relative
	}
	fmt.println("Start state: ", start)

	found: bool
	for s, i in res[startIndex:] {
		found = s == names[i]
		if !found {
			break
		}
	}
	fmt.println("Found: ", found)
}
