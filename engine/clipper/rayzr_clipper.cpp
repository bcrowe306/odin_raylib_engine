// The C interface the engine uses to Clipper2 (Angus Johnson, Boost Software
// License 1.0 - licenses/THIRD_PARTY_NOTICES.txt): polygon normalization
// (fill rules, self-intersections), boolean operations and offsetting, each
// returning a polygon tree flattened into arrays. Built with the Clipper2
// sources by scripts/build_clipper.sh; bound in clipper.odin.
#include "clipper2/clipper.h"
#include <cstdlib>
#include <cstring>
#include <vector>

using namespace Clipper2Lib;

extern "C" {

// rz_paths: contours (x, y pairs packed in xy, counts[i] points each);
// parents[i]: for a hole, the index of the outer ring it is cut from; -1
// for outer rings. Outer rings come before their holes.
typedef struct {
	double *xy;
	int *counts;
	int *parents;
	int contours;
	int points;
} rz_paths;

void rz_free(rz_paths *p) {
	if (!p) return;
	std::free(p->xy);
	std::free(p->counts);
	std::free(p->parents);
	std::memset(p, 0, sizeof(*p));
}

}  // extern "C"

static PathsD to_paths(const double *xy, const int *counts, int n) {
	PathsD out;
	out.reserve(n);
	int k = 0;
	for (int i = 0; i < n; ++i) {
		PathD p;
		p.reserve(counts[i]);
		for (int j = 0; j < counts[i]; ++j, k += 2) p.emplace_back(xy[k], xy[k + 1]);
		out.push_back(std::move(p));
	}
	return out;
}

static void emit(const PolyPathD &node, int outer, std::vector<double> &xy, std::vector<int> &counts, std::vector<int> &parents) {
	for (size_t i = 0; i < node.Count(); ++i) {
		const PolyPathD *c = node.Child(i);
		const PathD &poly = c->Polygon();
		int idx = (int)counts.size();
		for (const auto &pt : poly) {
			xy.push_back(pt.x);
			xy.push_back(pt.y);
		}
		counts.push_back((int)poly.size());
		parents.push_back(c->IsHole() ? outer : -1);
		// An outer's children are its holes; a hole's children are islands (outers).
		emit(*c, c->IsHole() ? -1 : idx, xy, counts, parents);
	}
}

static int to_result(const PolyTreeD &tree, rz_paths *out) {
	std::vector<double> xy;
	std::vector<int> counts, parents;
	emit(tree, -1, xy, counts, parents);
	out->contours = (int)counts.size();
	out->points = (int)(xy.size() / 2);
	out->xy = (double *)std::malloc(sizeof(double) * (xy.size() ? xy.size() : 1));
	out->counts = (int *)std::malloc(sizeof(int) * (counts.size() ? counts.size() : 1));
	out->parents = (int *)std::malloc(sizeof(int) * (parents.size() ? parents.size() : 1));
	if (!out->xy || !out->counts || !out->parents) {
		rz_free(out);
		return 0;
	}
	if (!xy.empty()) std::memcpy(out->xy, xy.data(), sizeof(double) * xy.size());
	if (!counts.empty()) std::memcpy(out->counts, counts.data(), sizeof(int) * counts.size());
	if (!parents.empty()) std::memcpy(out->parents, parents.data(), sizeof(int) * parents.size());
	return 1;
}

static FillRule fill_rule(int r) {return r == 1 ? FillRule::NonZero : r == 2 ? FillRule::Positive : r == 3 ? FillRule::Negative : FillRule::EvenOdd;}

extern "C" {

// rz_normalize: the area the contours cover under the fill rule (0 even-odd,
// 1 non-zero, 2 positive, 3 negative) as simple polygons: no
// self-intersections, holes assigned to their outer rings.
int rz_normalize(const double *xy, const int *counts, int n, int rule, int precision, rz_paths *out) {
	std::memset(out, 0, sizeof(*out));
	try {
		ClipperD c(precision);
		c.AddSubject(to_paths(xy, counts, n));
		PolyTreeD tree;
		if (!c.Execute(ClipType::Union, fill_rule(rule), tree)) return 0;
		return to_result(tree, out);
	} catch (...) {
		return 0;
	}
}

// rz_boolean: op 1 intersection, 2 union, 3 difference, 4 xor of subject
// and clip contours (closed).
int rz_boolean(int op, const double *sxy, const int *scounts, int sn, const double *cxy, const int *ccounts, int cn,
		int rule, int precision, rz_paths *out) {
	std::memset(out, 0, sizeof(*out));
	try {
		ClipperD c(precision);
		c.AddSubject(to_paths(sxy, scounts, sn));
		if (cn > 0) c.AddClip(to_paths(cxy, ccounts, cn));
		PolyTreeD tree;
		ClipType ct = op == 1 ? ClipType::Intersection : op == 2 ? ClipType::Union : op == 3 ? ClipType::Difference : ClipType::Xor;
		if (!c.Execute(ct, fill_rule(rule), tree)) return 0;
		return to_result(tree, out);
	} catch (...) {
		return 0;
	}
}

// rz_offset: grows (delta > 0) or shrinks closed contours, or outlines open
// ones (closed = 0): join 0 square, 1 bevel, 2 round, 3 miter; end (open
// contours) 2 butt, 3 square, 4 round.
int rz_offset(const double *xy, const int *counts, int n, int closed, double delta, int join, int end, double miter_limit,
		double arc_tolerance, int precision, rz_paths *out) {
	std::memset(out, 0, sizeof(*out));
	try {
		JoinType jt = join == 0 ? JoinType::Square : join == 1 ? JoinType::Bevel : join == 2 ? JoinType::Round : JoinType::Miter;
		EndType et = closed ? EndType::Polygon : end == 3 ? EndType::Square : end == 4 ? EndType::Round : EndType::Butt;
		PathsD grown = InflatePaths(to_paths(xy, counts, n), delta, jt, et, miter_limit, precision, arc_tolerance);
		ClipperD c(precision);
		c.AddSubject(grown);
		PolyTreeD tree;
		if (!c.Execute(ClipType::Union, FillRule::NonZero, tree)) return 0;
		return to_result(tree, out);
	} catch (...) {
		return 0;
	}
}

}  // extern "C"
