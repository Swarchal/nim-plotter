## A tri-state optional used throughout the grammar.
##
## `std/options` would do the job, but every call site would then read
## `Scale(zero = some(false))`. The implicit converter here lets the same
## thing be written `Scale(zero = false)`, which is what the Altair-shaped
## API needs. `Opt[T]()` is the unset state, and unset means "omit this key
## from the spec" — distinct from a key explicitly set to `false` or `""`.

type
  Opt*[T] = object
    has*: bool
    val*: T

converter toOpt*[T](x: T): Opt[T] =
  ## The reason this module exists. Never overload a proc on both `T` and
  ## `Opt[T]` — that is the one thing this converter cannot survive.
  Opt[T](has: true, val: x)

converter intToOptFloat*(x: int): Opt[float] =
  ## So `size = 60` works as well as `size = 60.0`.
  Opt[float](has: true, val: x.float)

proc opt*[T](x: T): Opt[T] = Opt[T](has: true, val: x)
proc unset*[T](): Opt[T] = Opt[T]()

proc isSome*[T](o: Opt[T]): bool = o.has
proc isNone*[T](o: Opt[T]): bool = not o.has
proc get*[T](o: Opt[T]): T = o.val
proc get*[T](o: Opt[T], fallback: T): T = (if o.has: o.val else: fallback)

proc `$`*[T](o: Opt[T]): string =
  if o.has: $o.val else: "unset"

proc `==`*[T](a, b: Opt[T]): bool =
  a.has == b.has and (not a.has or a.val == b.val)
