package engine


RenderLayer :: enum {
	Layer1,
	Layer2,
	Layer3,
	Layer4,
	Layer5,
	Layer6,
	Layer7,
	Layer8,
}

CollisionLayer :: enum u64 {
	Layer1  = 0,
	Layer2  = 1,
	Layer3  = 2,
	Layer4  = 3,
	Layer5  = 4,
	Layer6  = 5,
	Layer7  = 6,
	Layer8  = 7,
	Layer9  = 8,
	Layer10 = 9,
	Layer11 = 10,
	Layer12 = 11,
	Layer13 = 12,
	Layer14 = 13,
	Layer15 = 14,
	Layer16 = 15,
}

CollisionLayerSet :: bit_set[CollisionLayer; u64]

DEFAULT_COLLISION_CATEGORIES :: CollisionLayerSet{.Layer1}

DEFAULT_COLLISION_MASK :: CollisionLayerSet{
	.Layer1, .Layer2, .Layer3, .Layer4,
	.Layer5, .Layer6, .Layer7, .Layer8,
	.Layer9, .Layer10, .Layer11, .Layer12,
	.Layer13, .Layer14, .Layer15, .Layer16,
}

CollisionLayerSet_ToBits :: proc(set: CollisionLayerSet) -> u64 {
	return transmute(u64)set
}

CollisionLayerSet_FromBits :: proc(bits: u64) -> CollisionLayerSet {
	return transmute(CollisionLayerSet)bits
}
