
class Vec2:
    def __init__(self, x: float, y: float):
        self.x: float = x
        self.y: float = y

    def __add__(self, other):
        if isinstance(other, Vec2):
            return Vec2(self.x + other.x, self.y + other.y)
        elif isinstance(other, (float, int)):
            return Vec2(self.x + other, self.y + other)

    def __sub__(self, other):
        if isinstance(other, Vec2):
            return Vec2(self.x - other.x, self.y - other.y)
        elif isinstance(other, (float, int)):
            return Vec2(self.x - other, self.y - other)

    def __mul__(self, other):
        if isinstance(other, Vec2):
            return Vec2(self.x * other.x, self.y * other.y)
        elif isinstance(other, (float, int)):
            return Vec2(self.x * other, self.y * other)

    def __div__(self, other):
        if isinstance(other, Vec2):
            return Vec2(self.x / other.x, self.y / other.y)
        elif isinstance(other, (float, int)):
            return Vec2(self.x / other, self.y / other)

    def __repr__(self) -> str:
        return f"x: {self.x}, y: {self.y}"


class Node:
    def __init__(self, x: float, y: float):
        self.pos: Vec2 = Vec2(x, y)
        self.gPos: Vec2 = Vec2(0,0)
        self.parent: Node | None = None
        self.children: list[Node] = []

    def addChild(self, child: 'Node'):
        self.children.append(child)
        child.parent = self

    def getParent(self):
        return self.parent

    def hasParent(self):
        return self.parent != None

node1 = Node(1, 1)
node2 = Node(1,2)
node3 = Node(1, 0)
node4 = Node(2,2)

node1.addChild(node2)
node1.addChild(node3)
node2.addChild(node4)


def reduceNodes(node: Node):
    if not node.hasParent():
        node.gPos = node.pos
    for child in node.children:
        child.gPos = child.pos + node.gPos
        reduceNodes(child)


reduceNodes(node1)

print(node1.gPos)
print(node2.gPos)
print(node3.gPos)
print(node4.gPos)
