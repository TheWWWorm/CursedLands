/*
 * Native LZMA2 decoder for the GOG installer import (GDExtension, C).
 *
 * The same decoder as src/ei/lzma.gd (a port of Igor Pavlov's public
 * domain reference decoder LzmaSpec.cpp, LZMA2 framing as in xz), compiled so
 * that unpacking the installer takes seconds instead of most of an hour.
 * GDScript keeps its own decoder and uses it wherever this library is absent.
 * From the Demiurges engine's el_lzma.c (TheWWWorm, Apache-2.0).
 *
 * Exposed as static methods of the class InstallerLzmaKernel:
 *   open(packed: PackedByteArray, out_size: int) -> int
 *       starts decoding an Inno Setup file chunk (its dictionary-size byte,
 *       then LZMA2 chunks) into a buffer of out_size bytes; returns a handle
 *       or -1;
 *   step(handle: int, max_out: int) -> int
 *       decodes at least max_out more bytes (whole LZMA2 chunks) and returns
 *       the bytes decoded so far, or -1 when the data is damaged;
 *   take(handle: int) -> PackedByteArray
 *       returns the output (complete or not) and frees the handle.
 * Each handle is used by one thread at a time; different handles can be
 * stepped on different threads.
 */
#include <stdint.h>
#include <string.h>
#include <stdlib.h>

#include "include/gdextension_interface.h"

#if defined(_WIN32)
#define IL_EXPORT __declspec(dllexport)
#else
#define IL_EXPORT __attribute__((visibility("default")))
#endif

/* ------------------------------------------------------------------ decoder */

#define TOP (1u << 24)
#define PROB_INIT 1024
#define IS_MATCH 0
#define IS_REP 192
#define IS_REP_G0 204
#define IS_REP_G1 216
#define IS_REP_G2 228
#define IS_REP0_LONG 240
#define POS_SLOT 432
#define POS_DEC 688
#define ALIGN 803
#define LEN 819
#define REP_LEN 1333
#define PROBS 1847
/* LZMA2 allows lc + lp <= 4. */
#define LITERALS (0x300 << 4)

typedef struct {
	const uint8_t *s;
	int64_t sp, send;
	uint8_t *out;
	int64_t o, out_size;
	uint32_t range, code;
	uint32_t lc, lp, pb;
	int have_props;
	uint32_t state, rep0, rep1, rep2, rep3;
	int finished, failed;
	uint16_t p[PROBS];
	uint16_t lit[LITERALS];
} Decoder;

static inline uint32_t next_byte(Decoder *d) {
	uint32_t b = d->sp < d->send ? d->s[d->sp] : 0;
	d->sp++;
	return b;
}

static inline uint32_t bit(Decoder *d, uint16_t *prob) {
	uint32_t pr = *prob;
	uint32_t bound = (d->range >> 11) * pr;
	uint32_t b;
	if (d->code < bound) {
		d->range = bound;
		*prob = (uint16_t)(pr + ((2048 - pr) >> 5));
		b = 0;
	} else {
		d->range -= bound;
		d->code -= bound;
		*prob = (uint16_t)(pr - (pr >> 5));
		b = 1;
	}
	if (d->range < TOP) {
		d->range <<= 8;
		d->code = (d->code << 8) | next_byte(d);
	}
	return b;
}

static inline uint32_t tree(Decoder *d, uint16_t *p, uint32_t bits) {
	uint32_t m = 1;
	for (uint32_t i = 0; i < bits; i++) m = (m << 1) + bit(d, p + m);
	return m - (1u << bits);
}

static inline uint32_t rtree(Decoder *d, uint16_t *p, uint32_t bits) {
	uint32_t m = 1, sym = 0;
	for (uint32_t i = 0; i < bits; i++) {
		uint32_t b = bit(d, p + m);
		m = (m << 1) + b;
		sym |= b << i;
	}
	return sym;
}

static inline uint32_t direct(Decoder *d, uint32_t bits) {
	uint32_t res = 0;
	for (uint32_t i = 0; i < bits; i++) {
		d->range >>= 1;
		uint32_t b = 0;
		if (d->code >= d->range) {
			d->code -= d->range;
			b = 1;
		}
		res = (res << 1) | b;
		if (d->range < TOP) {
			d->range <<= 8;
			d->code = (d->code << 8) | next_byte(d);
		}
	}
	return res;
}

/* Length decoder: choice, choice2, low[16][8], mid[16][8], high[256]. */
static inline uint32_t length(Decoder *d, uint16_t *p, uint32_t pos_state) {
	if (bit(d, p) == 0) return tree(d, p + 2 + (pos_state << 3), 3);
	if (bit(d, p + 1) == 0) return 8 + tree(d, p + 2 + 128 + (pos_state << 3), 3);
	return 16 + tree(d, p + 2 + 256, 8);
}

static void reset_state(Decoder *d) {
	for (int i = 0; i < PROBS; i++) d->p[i] = PROB_INIT;
	uint32_t n = 0x300u << (d->lc + d->lp);
	for (uint32_t i = 0; i < n; i++) d->lit[i] = PROB_INIT;
	d->state = 0;
	d->rep0 = d->rep1 = d->rep2 = d->rep3 = 0;
}

/* One LZMA chunk: decodes until the output reaches o_end. 0 on success. */
static int lzma_chunk(Decoder *d, int64_t o_end) {
	uint16_t *p = d->p;
	uint8_t *out = d->out;
	int64_t o = d->o;
	const uint32_t pb_mask = (1u << d->pb) - 1;
	const uint32_t lp_mask = (1u << d->lp) - 1;
	const uint32_t lc = d->lc;
	while (o < o_end) {
		const uint32_t pos_state = (uint32_t)o & pb_mask;
		const uint32_t st = d->state;
		if (bit(d, p + IS_MATCH + (st << 4) + pos_state) == 0) {
			uint32_t prev = o > 0 ? out[o - 1] : 0;
			uint16_t *probs = d->lit + 0x300 * ((((uint32_t)o & lp_mask) << lc) + (prev >> (8 - lc)));
			uint32_t sym = 1;
			if (st >= 7) {
				uint32_t mb = out[o - d->rep0 - 1];
				while (sym < 0x100) {
					uint32_t mbit = (mb >> 7) & 1;
					mb <<= 1;
					uint32_t b = bit(d, probs + ((1 + mbit) << 8) + sym);
					sym = (sym << 1) | b;
					if (mbit != b) break;
				}
			}
			while (sym < 0x100) sym = (sym << 1) | bit(d, probs + sym);
			out[o++] = (uint8_t)sym;
			d->state = st < 4 ? 0 : (st < 10 ? st - 3 : st - 6);
			continue;
		}
		uint32_t len;
		if (bit(d, p + IS_REP + st)) {
			if (o == 0) return -1;
			if (bit(d, p + IS_REP_G0 + st) == 0) {
				if (bit(d, p + IS_REP0_LONG + (st << 4) + pos_state) == 0) {
					d->state = st < 7 ? 9 : 11;
					out[o] = out[o - d->rep0 - 1];
					o++;
					continue;
				}
			} else {
				uint32_t dist;
				if (bit(d, p + IS_REP_G1 + st) == 0) {
					dist = d->rep1;
				} else {
					if (bit(d, p + IS_REP_G2 + st) == 0) {
						dist = d->rep2;
					} else {
						dist = d->rep3;
						d->rep3 = d->rep2;
					}
					d->rep2 = d->rep1;
				}
				d->rep1 = d->rep0;
				d->rep0 = dist;
			}
			len = length(d, p + REP_LEN, pos_state);
			d->state = st < 7 ? 8 : 11;
		} else {
			d->rep3 = d->rep2;
			d->rep2 = d->rep1;
			d->rep1 = d->rep0;
			len = length(d, p + LEN, pos_state);
			d->state = st < 7 ? 7 : 10;
			uint32_t slot = tree(d, p + POS_SLOT + ((len < 3 ? len : 3) << 6), 6);
			if (slot < 4) {
				d->rep0 = slot;
			} else {
				uint32_t nd = (slot >> 1) - 1;
				uint32_t dist = (2 | (slot & 1)) << nd;
				if (slot < 14) {
					dist += rtree(d, p + POS_DEC + dist - slot, nd);
				} else {
					dist += direct(d, nd - 4) << 4;
					dist += rtree(d, p + ALIGN, 4);
				}
				d->rep0 = dist;
			}
		}
		len += 2;
		/* No end marker inside LZMA2; a distance before the start is damage. */
		if ((int64_t)d->rep0 >= o) return -1;
		int64_t need = o + len;
		if (need > o_end) need = o_end;
		const uint8_t *from = out + (o - d->rep0 - 1);
		if (d->rep0 + 1 >= len) {
			memcpy(out + o, from, (size_t)(need - o));
			o = need;
		} else {
			while (o < need) out[o++] = *from++;
		}
	}
	d->o = o;
	return 0;
}

/* Decodes whole LZMA2 chunks until the output reaches `target`. */
static void decode_until(Decoder *d, int64_t target) {
	while (!d->finished && !d->failed && d->o < target) {
		if (d->sp >= d->send) {
			d->finished = 1;
			break;
		}
		uint32_t c = next_byte(d);
		if (c == 0) {
			d->finished = 1;
			break;
		}
		if (c < 0x80) {
			/* Stored chunk (1: dictionary reset, 2: none). */
			if (c > 2) { d->failed = 1; break; }
			int64_t n = (int64_t)((next_byte(d) << 8) | next_byte(d)) + 1;
			if (d->sp + n > d->send || d->o + n > d->out_size) { d->failed = 1; break; }
			memcpy(d->out + d->o, d->s + d->sp, (size_t)n);
			d->sp += n;
			d->o += n;
			continue;
		}
		int64_t usize = (int64_t)((((c & 0x1F) << 16) | (next_byte(d) << 8) | next_byte(d)) + 1);
		int64_t psize = (int64_t)(((next_byte(d) << 8) | next_byte(d)) + 1);
		uint32_t mode = (c >> 5) & 3;
		if (mode >= 2) {
			uint32_t props = next_byte(d);
			if (props >= 225) { d->failed = 1; break; }
			d->lc = props % 9;
			props /= 9;
			d->lp = props % 5;
			d->pb = props / 5;
			if (d->lc + d->lp > 4) { d->failed = 1; break; }
			d->have_props = 1;
		}
		if (!d->have_props) { d->failed = 1; break; }
		if (mode >= 1) reset_state(d);
		int64_t next = d->sp + psize;
		if (next > d->send || d->o + usize > d->out_size) { d->failed = 1; break; }
		/* Range decoder: a zero byte, then four code bytes. */
		d->range = 0xFFFFFFFF;
		d->code = 0;
		d->sp++;
		for (int i = 0; i < 4; i++) d->code = (d->code << 8) | next_byte(d);
		if (lzma_chunk(d, d->o + usize) != 0) { d->failed = 1; break; }
		d->sp = next;
	}
	if (d->finished && d->o != d->out_size) d->failed = 1;
}

/* ------------------------------------------------------------ Godot binding */

static GDExtensionInterfaceGetProcAddress get_proc;
static GDExtensionClassLibraryPtr library;

static GDExtensionInterfaceVariantGetType variant_get_type;
static GDExtensionInterfacePackedByteArrayOperatorIndex pba_index;
static GDExtensionInterfacePackedByteArrayOperatorIndexConst pba_index_const;
static GDExtensionInterfaceStringNameNewWithLatin1Chars string_name_new;
static GDExtensionInterfaceStringNewWithLatin1Chars string_new;
static GDExtensionInterfaceClassdbRegisterExtensionClass6 register_class;
static GDExtensionInterfaceClassdbRegisterExtensionClassMethod register_method;
static GDExtensionInterfaceClassdbUnregisterExtensionClass unregister_class;
static GDExtensionPtrConstructor pba_new, pba_copy;
static GDExtensionPtrDestructor pba_free, string_name_free, string_free;
static GDExtensionPtrBuiltInMethod pba_size, pba_resize;
static GDExtensionTypeFromVariantConstructorFunc int_from_variant, pba_from_variant;
static GDExtensionVariantFromTypeConstructorFunc variant_from_int, variant_from_pba;

/* Opaque storage for builtin types (64-bit builds: PackedByteArray 16 bytes,
 * StringName and String 8). */
typedef struct { _Alignas(8) uint8_t data[16]; } PackedBytes;
typedef struct { _Alignas(8) uint8_t data[8]; } Name;
typedef struct { _Alignas(8) uint8_t data[8]; } Text;

#define SLOTS 32
typedef struct {
	volatile int used;
	Decoder *decoder;
	PackedBytes src;
	PackedBytes out;
} Slot;
static Slot slots[SLOTS];

static int64_t bytes_size(PackedBytes *b) {
	int64_t n = 0;
	pba_size(b, NULL, &n, 0);
	return n;
}

static int64_t native_open(PackedBytes *packed, int64_t out_size) {
	if (out_size < 0) return -1;
	int handle = -1;
	for (int i = 0; i < SLOTS; i++) {
		int expected = 0;
		if (__atomic_compare_exchange_n(&slots[i].used, &expected, 1, 0, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE)) {
			handle = i;
			break;
		}
	}
	if (handle < 0) return -1;
	Slot *s = &slots[handle];
	Decoder *d = (Decoder *)malloc(sizeof(Decoder));
	if (!d) {
		__atomic_store_n(&s->used, 0, __ATOMIC_RELEASE);
		return -1;
	}
	memset(d, 0, sizeof(Decoder));
	const GDExtensionConstTypePtr copy_args[1] = { packed };
	pba_copy(&s->src, copy_args);
	pba_new(&s->out, NULL);
	int64_t want = out_size;
	const GDExtensionConstTypePtr resize_args[1] = { &want };
	int64_t err = 0;
	pba_resize(&s->out, resize_args, &err, 1);
	int64_t n = bytes_size(&s->src);
	d->out_size = out_size;
	d->out = out_size > 0 ? pba_index(&s->out, 0) : NULL;
	d->s = n > 0 ? pba_index_const(&s->src, 0) : NULL;
	/* Inno Setup's dictionary-size byte comes first. */
	d->sp = 1;
	d->send = n;
	if (err != 0 || (out_size > 0 && d->out == NULL)) d->failed = 1;
	s->decoder = d;
	return handle;
}

static Slot *slot_of(int64_t handle) {
	if (handle < 0 || handle >= SLOTS || !__atomic_load_n(&slots[handle].used, __ATOMIC_ACQUIRE) || !slots[handle].decoder) return NULL;
	return &slots[handle];
}

static int64_t native_step(int64_t handle, int64_t max_out) {
	Slot *s = slot_of(handle);
	if (!s) return -1;
	Decoder *d = s->decoder;
	int64_t target = max_out > 0 && d->o + max_out < d->out_size ? d->o + max_out : d->out_size;
	decode_until(d, target);
	return d->failed ? -1 : d->o;
}

/* Moves the output into `result` (an uninitialised PackedByteArray). */
static void native_take(int64_t handle, PackedBytes *result) {
	Slot *s = slot_of(handle);
	if (!s) {
		pba_new(result, NULL);
		return;
	}
	const GDExtensionConstTypePtr args[1] = { &s->out };
	pba_copy(result, args);
	pba_free(&s->out);
	pba_free(&s->src);
	free(s->decoder);
	s->decoder = NULL;
	__atomic_store_n(&s->used, 0, __ATOMIC_RELEASE);
}

/* Calls: ptrcall passes the values themselves, call passes Variants. */
enum { M_OPEN, M_STEP, M_TAKE };

static void ptrcall(void *method, GDExtensionClassInstancePtr instance, const GDExtensionConstTypePtr *args, GDExtensionTypePtr ret) {
	(void)instance;
	switch ((intptr_t)method) {
	case M_OPEN:
		*(int64_t *)ret = native_open((PackedBytes *)args[0], *(const int64_t *)args[1]);
		break;
	case M_STEP:
		*(int64_t *)ret = native_step(*(const int64_t *)args[0], *(const int64_t *)args[1]);
		break;
	case M_TAKE: {
		/* `ret` holds a constructed PackedByteArray: replace it. */
		pba_free(ret);
		native_take(*(const int64_t *)args[0], (PackedBytes *)ret);
		break;
	}
	}
}

static const GDExtensionVariantType ARGS[3][2] = {
	{ GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, GDEXTENSION_VARIANT_TYPE_INT },
	{ GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_INT },
	{ GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_NIL },
};
static const int ARG_COUNT[3] = { 2, 2, 1 };

static void call(void *method, GDExtensionClassInstancePtr instance, const GDExtensionConstVariantPtr *args, GDExtensionInt count, GDExtensionVariantPtr ret, GDExtensionCallError *error) {
	(void)instance;
	int m = (int)(intptr_t)method;
	error->error = GDEXTENSION_CALL_OK;
	if (count < ARG_COUNT[m]) {
		error->error = GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS;
		error->expected = ARG_COUNT[m];
		return;
	}
	if (count > ARG_COUNT[m]) {
		error->error = GDEXTENSION_CALL_ERROR_TOO_MANY_ARGUMENTS;
		error->expected = ARG_COUNT[m];
		return;
	}
	for (int i = 0; i < ARG_COUNT[m]; i++) {
		if (variant_get_type(args[i]) != ARGS[m][i]) {
			error->error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT;
			error->argument = i;
			error->expected = ARGS[m][i];
			return;
		}
	}
	if (m == M_OPEN) {
		PackedBytes packed;
		int64_t size = 0;
		pba_from_variant(&packed, (GDExtensionVariantPtr)args[0]);
		int_from_variant(&size, (GDExtensionVariantPtr)args[1]);
		int64_t handle = native_open(&packed, size);
		pba_free(&packed);
		variant_from_int(ret, &handle);
	} else if (m == M_STEP) {
		int64_t handle = 0, max_out = 0;
		int_from_variant(&handle, (GDExtensionVariantPtr)args[0]);
		int_from_variant(&max_out, (GDExtensionVariantPtr)args[1]);
		int64_t done = native_step(handle, max_out);
		variant_from_int(ret, &done);
	} else {
		int64_t handle = 0;
		int_from_variant(&handle, (GDExtensionVariantPtr)args[0]);
		PackedBytes out;
		native_take(handle, &out);
		variant_from_pba(ret, &out);
		pba_free(&out);
	}
}

static Name class_name, parent_name, empty_name;
static Text empty_text;

static GDExtensionPropertyInfo info(GDExtensionVariantType type, Name *name) {
	GDExtensionPropertyInfo p;
	p.type = type;
	p.name = name;
	p.class_name = &empty_name;
	p.hint = 0;
	p.hint_string = &empty_text;
	p.usage = 6; /* PROPERTY_USAGE_DEFAULT */
	return p;
}

static void add_method(int m, const char *name, const char *arg0, const char *arg1, GDExtensionVariantType ret) {
	Name method, a0, a1;
	string_name_new(&method, name, 0);
	string_name_new(&a0, arg0, 0);
	string_name_new(&a1, arg1 ? arg1 : "", 0);
	GDExtensionPropertyInfo args[2] = { info(ARGS[m][0], &a0), info(ARGS[m][1], &a1) };
	GDExtensionClassMethodArgumentMetadata meta[2] = {
		ARGS[m][0] == GDEXTENSION_VARIANT_TYPE_INT ? GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_INT64 : GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE,
		ARGS[m][1] == GDEXTENSION_VARIANT_TYPE_INT ? GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_INT64 : GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE,
	};
	GDExtensionPropertyInfo ret_info = info(ret, &empty_name);
	GDExtensionClassMethodInfo mi;
	memset(&mi, 0, sizeof(mi));
	mi.name = &method;
	mi.method_userdata = (void *)(intptr_t)m;
	mi.call_func = call;
	mi.ptrcall_func = ptrcall;
	mi.method_flags = GDEXTENSION_METHOD_FLAG_STATIC;
	mi.has_return_value = 1;
	mi.return_value_info = &ret_info;
	mi.return_value_metadata = ret == GDEXTENSION_VARIANT_TYPE_INT ? GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_INT64 : GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE;
	mi.argument_count = (uint32_t)ARG_COUNT[m];
	mi.arguments_info = args;
	mi.arguments_metadata = meta;
	register_method(library, &class_name, &mi);
	string_name_free(&method);
	string_name_free(&a0);
	string_name_free(&a1);
}

static void free_instance(void *userdata, GDExtensionClassInstancePtr instance) {
	(void)userdata;
	(void)instance;
}

static void initialize(void *userdata, GDExtensionInitializationLevel level) {
	(void)userdata;
	if (level != GDEXTENSION_INITIALIZATION_SCENE) return;
	string_name_new(&class_name, "InstallerLzmaKernel", 0);
	string_name_new(&parent_name, "Object", 0);
	string_name_new(&empty_name, "", 0);
	string_new(&empty_text, "");
	GDExtensionClassCreationInfo6 ci;
	memset(&ci, 0, sizeof(ci));
	ci.is_abstract = 1;
	ci.is_exposed = 1;
	ci.free_instance_func = free_instance;
	register_class(library, &class_name, &parent_name, &ci);
	add_method(M_OPEN, "open", "packed", "out_size", GDEXTENSION_VARIANT_TYPE_INT);
	add_method(M_STEP, "step", "handle", "max_out", GDEXTENSION_VARIANT_TYPE_INT);
	add_method(M_TAKE, "take", "handle", NULL, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
}

static void deinitialize(void *userdata, GDExtensionInitializationLevel level) {
	(void)userdata;
	if (level != GDEXTENSION_INITIALIZATION_SCENE) return;
	unregister_class(library, &class_name);
	string_name_free(&class_name);
	string_name_free(&parent_name);
	string_name_free(&empty_name);
	string_free(&empty_text);
}

#define LOAD(var, type, name) var = (type)get_proc(name); if (!var) return 0

IL_EXPORT GDExtensionBool installer_lzma_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	get_proc = p_get_proc_address;
	library = p_library;
	LOAD(variant_get_type, GDExtensionInterfaceVariantGetType, "variant_get_type");
	LOAD(pba_index, GDExtensionInterfacePackedByteArrayOperatorIndex, "packed_byte_array_operator_index");
	LOAD(pba_index_const, GDExtensionInterfacePackedByteArrayOperatorIndexConst, "packed_byte_array_operator_index_const");
	LOAD(string_name_new, GDExtensionInterfaceStringNameNewWithLatin1Chars, "string_name_new_with_latin1_chars");
	LOAD(string_new, GDExtensionInterfaceStringNewWithLatin1Chars, "string_new_with_latin1_chars");
	LOAD(register_class, GDExtensionInterfaceClassdbRegisterExtensionClass6, "classdb_register_extension_class6");
	LOAD(register_method, GDExtensionInterfaceClassdbRegisterExtensionClassMethod, "classdb_register_extension_class_method");
	LOAD(unregister_class, GDExtensionInterfaceClassdbUnregisterExtensionClass, "classdb_unregister_extension_class");
	GDExtensionInterfaceVariantGetPtrConstructor get_constructor;
	GDExtensionInterfaceVariantGetPtrDestructor get_destructor;
	GDExtensionInterfaceVariantGetPtrBuiltinMethod get_method;
	GDExtensionInterfaceGetVariantToTypeConstructor get_to_type;
	GDExtensionInterfaceGetVariantFromTypeConstructor get_from_type;
	LOAD(get_constructor, GDExtensionInterfaceVariantGetPtrConstructor, "variant_get_ptr_constructor");
	LOAD(get_destructor, GDExtensionInterfaceVariantGetPtrDestructor, "variant_get_ptr_destructor");
	LOAD(get_method, GDExtensionInterfaceVariantGetPtrBuiltinMethod, "variant_get_ptr_builtin_method");
	LOAD(get_to_type, GDExtensionInterfaceGetVariantToTypeConstructor, "get_variant_to_type_constructor");
	LOAD(get_from_type, GDExtensionInterfaceGetVariantFromTypeConstructor, "get_variant_from_type_constructor");
	pba_new = get_constructor(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, 0);
	pba_copy = get_constructor(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, 1);
	pba_free = get_destructor(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	string_name_free = get_destructor(GDEXTENSION_VARIANT_TYPE_STRING_NAME);
	string_free = get_destructor(GDEXTENSION_VARIANT_TYPE_STRING);
	Name size_name, resize_name;
	string_name_new(&size_name, "size", 0);
	string_name_new(&resize_name, "resize", 0);
	pba_size = get_method(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, &size_name, 3173160232);
	pba_resize = get_method(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, &resize_name, 848867239);
	string_name_free(&size_name);
	string_name_free(&resize_name);
	int_from_variant = get_to_type(GDEXTENSION_VARIANT_TYPE_INT);
	pba_from_variant = get_to_type(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	variant_from_int = get_from_type(GDEXTENSION_VARIANT_TYPE_INT);
	variant_from_pba = get_from_type(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	if (!pba_new || !pba_copy || !pba_free || !string_name_free || !string_free || !pba_size || !pba_resize
			|| !int_from_variant || !pba_from_variant || !variant_from_int || !variant_from_pba)
		return 0;
	r_initialization->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE;
	r_initialization->userdata = NULL;
	r_initialization->initialize = initialize;
	r_initialization->deinitialize = deinitialize;
	return 1;
}
