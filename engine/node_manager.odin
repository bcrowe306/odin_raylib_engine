package engine

import "core:log"
import "core:math"
import "core:container/queue"
import vmem "core:mem/virtual"
import "core:strings"

// The hierarchy is indexed both ways (parent -> ordered children, child ->
// parent) so lookups are O(1) instead of scanning a flat relationship list
// (which made every frame O(n²) in the node count).
NodeManager :: struct {
	nodes: [dynamic]^Node,
	addition: [dynamic]^Node,
	removal: [dynamic]^Node,
	childrenOf: map[^Node][dynamic]^Node,
	parentOf: map[^Node]^Node,
	free: queue.Queue(int),
	arena: vmem.Arena,
	// VisibilityNotifierNodes in the manager (added / removed with them),
	// so the per-frame visibility pass touches only those.
	notifiers: [dynamic]^Node,
	// NavigationRegion / NavigationAgent nodes (navigation_nodes.odin).
	navRegions: [dynamic]^Node,
	navAgents:  [dynamic]^Node,
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
	manager.nodes = nil
	manager.addition = nil
	manager.removal = nil
	manager.childrenOf = make(map[^Node][dynamic]^Node)
	manager.parentOf = make(map[^Node]^Node)
	manager.notifiers = nil
	err := vmem.arena_init_growing(&manager.arena)
	if err != nil {
		log.error(err)
	}
	queue.init(&manager.free)
}

NodeManager_Terminate :: proc(manager: ^NodeManager) {
	if manager == nil do return

	// Terminate any nodes still active or queued
	for node in manager.nodes {
		if node != nil {
			Node_Terminate(node)
		}
	}
	for addNode in manager.addition {
		if addNode != nil {
			alreadyInNodes := false
			for n in manager.nodes {
				if n == addNode {
					alreadyInNodes = true
					break
				}
			}
			if !alreadyInNodes {
				Node_Terminate(addNode)
			}
		}
	}

	delete(manager.addition)
	delete(manager.removal)
	delete(manager.nodes)
	delete(manager.notifiers)
	delete(manager.navRegions)
	delete(manager.navAgents)
	for _, list in manager.childrenOf do delete(list)
	delete(manager.childrenOf)
	delete(manager.parentOf)
	queue.destroy(&manager.free)
	vmem.arena_destroy(&manager.arena)

	manager.addition = nil
	manager.removal = nil
	manager.nodes = nil
	manager.notifiers = nil
	manager.navRegions = nil
	manager.navAgents = nil
	manager.childrenOf = nil
	manager.parentOf = nil
}

// GetChildrenView returns a node's children in order without allocating.
// The slice is invalidated by AddChild/RemoveChild on the same parent; copy
// it (GetChildren / GetChildrenTemp) when the loop may change the hierarchy.
GetChildrenView :: proc(manager: ^NodeManager, parent: ^Node) -> []^Node {
	if list, ok := manager.childrenOf[parent]; ok do return list[:]
	return nil
}

// GetChildrenTemp copies a node's children into the temp allocator.
GetChildrenTemp :: proc(manager: ^NodeManager, parent: ^Node) -> []^Node {
	view := GetChildrenView(manager, parent)
	if len(view) == 0 do return nil
	out := make([]^Node, len(view), context.temp_allocator)
	copy(out, view)
	return out
}

// This allocates. Need to clean up when done
GetChildren :: proc(manager: ^NodeManager, parent: ^Node) -> [dynamic]^Node {
	nodes: [dynamic]^Node = make([dynamic]^Node)
	append(&nodes, ..GetChildrenView(manager, parent))
	return nodes
}

GetChild :: proc(manager: ^NodeManager, parent: ^Node) -> (node: ^Node, found: bool) {
	view := GetChildrenView(manager, parent)
	if len(view) > 0 do return view[0], true
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
	for child in GetChildrenView(manager, parent) {
		if child.name == name do return child, true
	}
	return nil, false
}

GetParent :: proc(manager: ^NodeManager, node: ^Node) -> ^Node {
	return manager.parentOf[node]
}

GetRootNode :: proc(scene: ^Scene) -> ^Node {
	return scene.rootNode
}

HasParent :: proc(manager: ^NodeManager, node: ^Node) -> bool {
	_, ok := manager.parentOf[node]
	return ok
}


// RemoveNode queues a node and its subtree for removal (at the end of the
// frame). A node taken from a pool goes back to its pool instead.
RemoveNode :: proc(manager: ^NodeManager, node: ^Node) {
	if node == nil || node.removing do return
	if node.pool != nil && node.enabled && Pool_Return(manager, node, node.gameContext) do return
	remove_tree(manager, node)
}

@(private = "file")
remove_tree :: proc(manager: ^NodeManager, node: ^Node) {
	if node == nil || node.removing do return
	node.removing = true
	for child in GetChildrenTemp(manager, node) do remove_tree(manager, child)
	append(&manager.removal, node)
}



ProcessNodeQueues :: proc(manager: ^NodeManager, gameContext: ^GameContext) {
	// Remove. The parents' child lists lose their removed children in one
	// pass each (removing them one by one is quadratic for big scenes).
	filtered := make(map[^Node]bool, context.temp_allocator)
	for n in manager.removal {
		if parent, ok := manager.parentOf[n]; ok && !parent.removing && parent not_in filtered {
			filtered[parent] = true
			if list, has := manager.childrenOf[parent]; has {
				keep := 0
				for c in list do if !c.removing {list[keep] = c; keep += 1}
				resize(&list, keep)
				manager.childrenOf[parent] = list
			}
		}
	}
	for removingNode in manager.removal {
		// Remove relationships (to its parent and to its children).
		if parent, ok := manager.parentOf[removingNode]; ok {
			Node_NotifyEvent(parent, .Child_Removed, removingNode, gameContext)
			Node_NotifyEvent(removingNode, .Parent_Removed, parent, gameContext)
			if parent in filtered {
				if p, has := manager.parentOf[removingNode]; has && p == parent do delete_key(&manager.parentOf, removingNode)
			} else {
				unlink(manager, parent, removingNode)
			}
		}
		for child in GetChildrenTemp(manager, removingNode) {
			Node_NotifyEvent(removingNode, .Child_Removed, child, gameContext)
			Node_NotifyEvent(child, .Parent_Removed, removingNode, gameContext)
			unlink(manager, removingNode, child)
		}
		if list, ok := manager.childrenOf[removingNode]; ok {
			delete(list)
			delete_key(&manager.childrenOf, removingNode)
		}

		// Remove nodes from manager. No modify node array. use free list
		index := removingNode.managerIndex - 1
		if index < 0 || index >= len(manager.nodes) || manager.nodes[index] != removingNode {
			index = -1
			for node, i in manager.nodes do if node == removingNode {index = i; break}
		}
		if index >= 0 {
			node := removingNode
			log.debug("Removing node from tree: ", node)
			node.gameContext = gameContext
			Node_NotifyEvent(node, .Exited_Tree, nil, gameContext)

			if node.pool != nil do Pool_Forget(node) // freed with its parent (not returned)
			if node.typeId == VisibilityNotifierNode {
				for n, k in manager.notifiers do if n == node {unordered_remove(&manager.notifiers, k); break}
			}
			if node.typeId == NavigationRegionNode {
				for n, k in manager.navRegions do if n == node {unordered_remove(&manager.navRegions, k); break}
			}
			if node.typeId == NavigationAgentNode {
				for n, k in manager.navAgents do if n == node {unordered_remove(&manager.navAgents, k); break}
			}
			// Frees node's arena, subjects, and any custom onDestroy resources.
			Node_Terminate(node)
			manager.nodes[index] = nil
			queue.push_back(&manager.free, index)
		} else {
			removingNode.removing = false // not in the list (yet): it stays
		}
	}
	clear(&manager.removal)


	// Addition. Notify "entered_tree" after the whole batch is in, so
	// handlers can see their new siblings/children.
	added := make([dynamic]^Node, context.temp_allocator)
	for addNode in manager.addition {
		if addNode != nil {
			addNode.gameContext = gameContext
		}
		index, ok := queue.pop_back_safe(&manager.free)
		if ok {
			log.debug("Adding node using free list")
			manager.nodes[index] = addNode
		}
		else {
			log.debug("Adding node")
			append(&manager.nodes, addNode)
			index = len(manager.nodes) - 1
		}
		if addNode != nil do addNode.managerIndex = index + 1
		if addNode != nil do append(&added, addNode)
		if addNode != nil && addNode.typeId == VisibilityNotifierNode do append(&manager.notifiers, addNode)
		if addNode != nil && addNode.typeId == NavigationRegionNode do append(&manager.navRegions, addNode)
		if addNode != nil && addNode.typeId == NavigationAgentNode do append(&manager.navAgents, addNode)
	}
	clear(&manager.addition)
	for n in added {
		if Node_IsAlive(n) do Node_NotifyEvent(n, .Entered_Tree, nil, gameContext)
	}
}


// Node_SetGlobalPositions composes transforms down the tree: a child's
// position is scaled and rotated by its parent (so children orbit and scale
// with their parent), scales multiply and rotations add.
Node_SetGlobalPositions :: proc(manager: ^NodeManager, node: ^Node, positionOffset: [2]f32 = {0,0}, scaleOffset: [2]f32 = {1, 1}, rotationOffset: f32 = 0) {
	if node == nil {
		return
	}
	node.globalPosition = positionOffset + rotate_vec(node.position * scaleOffset, rotationOffset)
	node.globalScale = node.scale * scaleOffset
	node.globalRotation = node.rotation + rotationOffset
	for child in GetChildrenView(manager, node) {
		Node_SetGlobalPositions(manager, child, node.globalPosition, node.globalScale, node.globalRotation)
	}
}

// Node_ComputeWorldPosition: a node's world position from its parent chain,
// for when globalPosition isn't up to date yet (e.g. during ready).
Node_ComputeWorldPosition :: proc(manager: ^NodeManager, node: ^Node) -> [2]f32 {
	chain := make([dynamic]^Node, context.temp_allocator)
	for n := node; n != nil; n = GetParent(manager, n) do append(&chain, n)
	pos, scl, rot := [2]f32{0, 0}, [2]f32{1, 1}, f32(0)
	#reverse for n in chain {
		pos = pos + rotate_vec(n.position * scl, rot)
		scl *= n.scale
		rot += n.rotation
	}
	return pos
}

@(private)
rotate_vec :: proc(v: [2]f32, degrees: f32) -> [2]f32 {
	if degrees == 0 do return v
	r := math.to_radians(degrees)
	c, s := math.cos(r), math.sin(r)
	return {v.x * c - v.y * s, v.x * s + v.y * c}
}

// Node_ParentToWorld / Node_WorldToParent convert points between world space
// and the space a node's `position` is expressed in (its parent's space).
Node_WorldToParent :: proc(manager: ^NodeManager, node: ^Node, world: [2]f32) -> [2]f32 {
	parent := GetParent(manager, node)
	if parent == nil do return world
	local := rotate_vec(world - parent.globalPosition, -parent.globalRotation)
	sx := parent.globalScale.x if parent.globalScale.x != 0 else 1
	sy := parent.globalScale.y if parent.globalScale.y != 0 else 1
	return {local.x / sx, local.y / sy}
}

Node_ParentToWorld :: proc(manager: ^NodeManager, node: ^Node, local: [2]f32) -> [2]f32 {
	parent := GetParent(manager, node)
	if parent == nil do return local
	return parent.globalPosition + rotate_vec(local * parent.globalScale, parent.globalRotation)
}

AddChild :: proc(manager: ^NodeManager, parent, child: ^Node) {
	if parent == child {
		log.error("Child node cannot be it's own parent")
		return
	}
	if existing, has := manager.parentOf[child]; has {
		if existing == parent {
			log.error("Parent already has child")
			return
		}
		// A node has one parent: moving it detaches it from the old one.
		unlink(manager, existing, child)
	}
	list := manager.childrenOf[parent]
	append(&list, child)
	manager.childrenOf[parent] = list
	manager.parentOf[child] = parent
	ctx := parent.gameContext if parent.gameContext != nil else child.gameContext
	Node_NotifyEvent(parent, .Child_Added, child, ctx)
	Node_NotifyEvent(child, .Parent_Added, parent, ctx)
}

// MoveChild moves a child to position `index` among its siblings.
MoveChild :: proc(manager: ^NodeManager, parent, child: ^Node, index: int) {
	list, ok := manager.childrenOf[parent]
	if !ok do return
	for c, i in list {
		if c == child {
			ordered_remove(&list, i)
			break
		}
	}
	inject_at(&list, clamp(index, 0, len(list)), child)
	manager.childrenOf[parent] = list
}

RemoveChild :: proc(manager: ^NodeManager, parent, child: ^Node) {
	if p, ok := manager.parentOf[child]; !ok || p != parent {
		log.error("Child Relationship not found. Cannot remove")
		return
	}
	unlink(manager, parent, child)
}

// unlink removes a parent/child link, keeping the sibling order.
@(private = "file")
unlink :: proc(manager: ^NodeManager, parent, child: ^Node) {
	if list, ok := manager.childrenOf[parent]; ok {
		for c, i in list {
			if c == child {
				ordered_remove(&list, i)
				break
			}
		}
		manager.childrenOf[parent] = list
	}
	if p, ok := manager.parentOf[child]; ok && p == parent {
		delete_key(&manager.parentOf, child)
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
			startingNode = parent
	}

	foundNode := startingNode
	for part in parts[startingIndex:] {
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
		foundNode = child
	}


	return foundNode, true
}
