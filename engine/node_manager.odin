package engine

import "core:log"
import "core:container/queue"
import vmem "core:mem/virtual"
import rl "vendor:raylib"
import "core:strings"

NodeManager :: struct {
	nodes: [dynamic]^Node,
	addition: [dynamic]^Node,
	removal: [dynamic]^Node,
	relationships: [dynamic][2]^Node,
	free: queue.Queue(int),
	arena: vmem.Arena,
}

NodeManagerStats :: struct {
	capacity: int,
	count: int,
	free: int,
}


NodeManager_GetStats :: proc(manager: ^NodeManager) -> NodeManagerStats {
	cap := len(manager.nodes)
	free := queue.len(manager.free)
	count: = cap - free
	return NodeManagerStats{
		capacity = cap,
		free = free,
		count = count
	}
}

NodeManager_Init :: proc(manager: ^NodeManager) {
	err := vmem.arena_init_growing(&manager.arena)
	if err != nil {
		log.error(err)
	}
}

NodeManager_Terminate :: proc(manager: ^NodeManager) {
	delete(manager.addition)
	delete(manager.removal)
	delete(manager.nodes)
	free(&manager.free)
	free(&manager.arena)
}

// This allocates. Need to clean up when done
GetChildren :: proc(manager: ^NodeManager, parent: ^Node) -> [dynamic]^Node {
	nodes :[dynamic]^Node = make([dynamic]^Node)
	for rel in manager.relationships {
		if rel[0] ==parent {
			append(&nodes, rel[1])
		}
	}
	return nodes
}

GetChild :: proc(manager: ^NodeManager, parent: ^Node) -> (node: ^Node, found: bool) {
	for rel in manager.relationships {
		if rel[0] == parent {
			return rel[1], true
		}
	}
	return nil, false
}

GetChildByName :: proc(manager: ^NodeManager, parent: ^Node, name: string) -> (node: ^Node, found: bool) {
	if parent == nil {
		log.error("Parent node is nil. Cannot get child by name")
		return nil, false
	}

	if name == "" {
		log.error("Child name is empty. Cannot get child by name")
		return nil, false
	}
	for rel in manager.relationships {
		if rel[0] == parent && rel[1].name == name {
			return rel[1], true
		}
	}
	return nil, false
}

GetParent :: proc(manager: ^NodeManager, node: ^Node) -> ^Node {
	for rel in manager.relationships {
		if rel[1] == node {
			return rel[0]
		}
	}
	return nil
}

GetRootNode :: proc(scene: ^Scene) -> ^Node {
	return scene.rootNode
}

HasParent :: proc(manager: ^NodeManager, node: ^Node) -> bool {
	for rel in manager.relationships {
		if rel[1] == node do return true
	}
	return false
}


RemoveNode :: proc(manager: ^NodeManager, node: ^Node) {
	children := GetChildren(manager, node)
	defer delete(children)
	if len(children) > 0 {
		for child in children {
			RemoveNode(manager, child)
		}
	}
	append(&manager.removal, node)
}



ProcessNodeQueues :: proc(manager: ^NodeManager, gameContext: ^GameContext) {
	// Remove
	for removingNode in manager.removal {
		// Remove Relationships
		rRels :[dynamic][2]^Node

		for rel, relIndex in manager.relationships{
			if rel[0] == removingNode || rel[1] == removingNode {
				append(&rRels, rel)
			}
		}

		for rRel in rRels {
			for rel, index in manager.relationships {
				if rel == rRel {
					log.debug("Removing relationship: ", rel)
					rel[0].onChildRemoved->notify(rel[0], false, gameContext)
					rel[1].onParentRemoved->notify(rel[1], false, gameContext)
					unordered_remove(&manager.relationships, index)
					break
				}
			}
		}
		delete(rRels)

		// Remove nodes from manager. No modify node array. use free list
		for node, index in manager.nodes {
			if removingNode == node {
				log.debug("Removing node from tree: ", node)
				node.onExit->notify(node, false, gameContext)

				// This can be used to clean up resources on any custom node
				if node.onDestroy != nil do node->onDestroy(gameContext)
				manager.nodes[index] = nil
				queue.push_back(&manager.free, index)
			}
		}
	}
	clear(&manager.removal)


	// Addition
	for addNode in manager.addition {
		index, ok := queue.pop_back_safe(&manager.free)
		if ok {
			log.debug("Adding node using free list")
			manager.nodes[index] = addNode
		}
		else {
			log.debug("Adding node")
			append(&manager.nodes, addNode)
		}
	}
	clear(&manager.addition)
}


Node_SetGlobalPositions :: proc(manager: ^NodeManager, node: ^Node, positionOffset: [2]f32 = {0,0}, scaleOffset: [2]f32 = {1, 1}, rotationOffset: f32 = 0) {
	if node == nil {
		return
	}
	node.globalPosition = node.position + positionOffset
	node.globalScale = node.scale * scaleOffset
	node.globalRotation = node.rotation + rotationOffset
	children := GetChildren(manager, node)
	defer delete(children)
	for child in children {
		Node_SetGlobalPositions(manager, child, node.globalPosition)
	}
}



AddChild :: proc(manager: ^NodeManager, parent, child: ^Node) {
	found := false
	if parent == child {
		log.error("Child node cannot be it's own parent")
		return
	}

	// Check if relationship already exists
	for rel in manager.relationships {
		if rel[0] == parent && rel[1] == child do found = true
	}

	if !found {
		append(&manager.relationships, [2]^Node{parent, child})
	}
	else {
		log.error("Parent already has child")
	}
}

RemoveChild :: proc(manager: ^NodeManager, parent, child: ^Node) {
	i := -1
	for rel, index in manager.relationships {
		if rel[0] == parent && rel[1] == child {
			i = index
		}
	}

	if i != -1 {
		unordered_remove(&manager.relationships, i)
	}
	else {
		log.error("Child Relationship not found. Cannot remove")
	}
}

PathStartState :: enum {
	Root,
	Relative,
	Parent,
}

GetNodeByPath :: proc(scene: ^Scene, currentNode: ^Node, path: string) -> (node: ^Node, found: bool) {
	if path == "" {
		log.error("Path is empty. Cannot get node by path")
		return nil, false
	}

	parts, err := strings.split(path, "/")
	if err != nil {
		log.error("Error splitting path: ", err)
		return nil, false
	}
	defer delete(parts)

	if len(parts) == 0 {
		log.error("Path is empty after splitting. Cannot get node by path")
		return nil, false
	}

	if parts[1] == "" {

	}

	startState : PathStartState
	startingIndex := 0
	if parts[0] == "" {
		startState = PathStartState.Root
		startingIndex = 1
	}
	else if parts[0] == "." {
		startState = PathStartState.Relative
		startingIndex = 1
	}
	else if parts[0] == ".." {
		startState = PathStartState.Parent
		startingIndex = 1
	}
	else {
		startState = PathStartState.Relative
		startingIndex = 0
	}

	startingNode := scene.rootNode
	switch startState {
		case .Root:
			startingNode = scene.rootNode
		case .Relative:
			startingNode = currentNode
		case .Parent:
			parent := GetParent(scene.manager, currentNode)
			if parent == nil {
				log.error("Current node has no parent. Cannot get node by path")
				return nil, false
			}
	}

	for part, i in parts[startingIndex:] {
		if part == "" || part == "." || part == ".." {
			log.error("Path part is empty, relative, or parent. Cannot get node by path")
			return nil, false
		}

		child, found := GetChildByName(scene.manager, startingNode, part)
		if !found {
			log.error("Child node not found: ", part)
			return nil, false
		}
		startingNode = child
	}


	return currentNode, true
}
