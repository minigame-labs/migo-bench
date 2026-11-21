-- Live native heap of one process at the end of a heapprofd window, attributed to the first frame outside the
-- allocator: by component, and the largest call sites. Input: a symbolized trace (heap-profile.sh).
--
-- heapprofd records sampled mallocs and frees per call site; their sum per site is what is still allocated when the
-- window closes. A frame belongs to "the allocator" when it is malloc itself, libc/libc++ plumbing, or a Rust / C++
-- allocation helper whose caller is the real answer; the deepest frame that is not one is the site.

DROP TABLE IF EXISTS live;
CREATE TABLE live AS
SELECT callsite_id, SUM(size) AS bytes, SUM(count) AS n
FROM heap_profile_allocation
GROUP BY callsite_id
HAVING bytes > 0;

DROP TABLE IF EXISTS chain;
CREATE TABLE chain AS
WITH RECURSIVE c(leaf, id, depth, frame_id, parent_id) AS (
  SELECT s.id, s.id, s.depth, s.frame_id, s.parent_id
  FROM stack_profile_callsite s JOIN live l ON l.callsite_id = s.id
  UNION ALL
  SELECT c.leaf, p.id, p.depth, p.frame_id, p.parent_id
  FROM c JOIN stack_profile_callsite p ON p.id = c.parent_id
)
SELECT
  c.leaf,
  c.depth,
  m.name AS lib,
  COALESCE(
    -- The outermost entry of an inlined chain is the function the code belongs to.
    (SELECT y.name FROM stack_profile_symbol y WHERE y.symbol_set_id = f.symbol_set_id ORDER BY y.id DESC LIMIT 1),
    NULLIF(f.name, ''),
    printf('%s+0x%x', m.name, f.rel_pc)
  ) AS fn
FROM c
JOIN stack_profile_frame f ON f.id = c.frame_id
JOIN stack_profile_mapping m ON m.id = f.mapping;

DROP TABLE IF EXISTS site;
CREATE TABLE site AS
SELECT leaf, lib, fn FROM (
  SELECT leaf, lib, fn, ROW_NUMBER() OVER (PARTITION BY leaf ORDER BY depth DESC) AS rn
  FROM chain
  WHERE NOT (
       lib LIKE '%/libc.so' OR lib LIKE '%/libc++%' OR lib LIKE '%heapprofd%' OR lib LIKE '%/libc_malloc%'
    OR lib LIKE '%/ld-android.so' OR lib LIKE '%/linker64'
    OR fn GLOB '*malloc*' OR fn GLOB '*calloc*' OR fn GLOB '*realloc*' OR fn GLOB '*memalign*'
    OR fn GLOB 'operator new*' OR fn GLOB '__rust_alloc*' OR fn GLOB '__rust_realloc*' OR fn GLOB '__rdl_*'
    OR fn GLOB 'alloc::*' OR fn GLOB '<alloc::*' OR fn GLOB 'hashbrown::*' OR fn GLOB '<hashbrown::*'
    OR fn GLOB 'std::__ndk1::*alloc*' OR fn GLOB 'std::__Cr::*alloc*' OR fn GLOB 'core::ptr::*'
    OR fn GLOB 'v8::internal::Malloced::*' OR fn GLOB 'v8::internal::AlignedAlloc*' OR fn GLOB 'v8::base::Malloc*'
    OR fn GLOB 'sk_malloc*' OR fn GLOB 'sk_realloc*' OR fn GLOB 'uprv_malloc*' OR fn GLOB 'icu_77::UMemory::*'
  )
) WHERE rn = 1;

DROP TABLE IF EXISTS attributed;
CREATE TABLE attributed AS
SELECT
  l.bytes, l.n,
  COALESCE(s.fn, '(allocator frames only)') AS fn,
  COALESCE(s.lib, '') AS lib,
  CASE
    WHEN s.fn IS NULL THEN 'allocator only'
    WHEN s.lib NOT LIKE '%libmigo.so' THEN 'outside libmigo: ' || replace(s.lib, rtrim(s.lib, replace(s.lib, '/', '')), '')
    WHEN s.fn GLOB 'v8::*' OR s.fn GLOB 'v8_inspector::*' OR s.fn GLOB 'cppgc::*' OR s.fn GLOB 'heap::base::*' THEN 'V8'
    WHEN s.fn GLOB 'icu_77::*' OR s.fn GLOB 'u*_77' THEN 'ICU'
    WHEN s.fn GLOB 'Sk*' OR s.fn GLOB '*::Sk*' OR s.fn GLOB 'Gr*' OR s.fn GLOB 'skia*' OR s.fn GLOB 'sk_*'
      OR s.fn GLOB 'skgpu::*' OR s.fn GLOB 'skia_private::*' OR s.fn GLOB 'skif::*' OR s.fn GLOB 'skjpeg*'
      OR s.fn GLOB 'skcms*' OR s.fn GLOB 'SkSL::*' THEN 'Skia'
    WHEN s.fn GLOB 'hb_*' OR s.fn GLOB 'OT::*' OR s.fn GLOB 'AAT::*' THEN 'HarfBuzz'
    WHEN s.fn GLOB 'FT_*' OR s.fn GLOB 'ft_*' OR s.fn GLOB 'tt_*' THEN 'FreeType'
    WHEN s.fn GLOB 'sqlite3*' THEN 'SQLite'
    WHEN s.fn GLOB 'deno_core::*' OR s.fn GLOB '<deno_core::*' OR s.fn GLOB 'serde_v8::*' THEN 'deno_core'
    WHEN s.fn GLOB 'tokio::*' OR s.fn GLOB '<tokio::*' THEN 'tokio'
    WHEN s.fn GLOB 'migo_*' OR s.fn GLOB '<migo_*' OR s.fn GLOB 'graphics::*' OR s.fn GLOB '<graphics::*'
      OR s.fn GLOB 'runtime_v8::*' OR s.fn GLOB '<runtime_v8::*' OR s.fn GLOB 'shared::*' OR s.fn GLOB '<shared::*'
      OR s.fn GLOB 'audio::*' OR s.fn GLOB 'io::*' OR s.fn GLOB 'core::*migo*' OR s.fn GLOB 'Java_*' THEN 'Migo'
    WHEN s.fn GLOB 'std::*' OR s.fn GLOB '<std::*' OR s.fn GLOB 'core::*' OR s.fn GLOB '<core::*' THEN 'Rust std'
    ELSE 'other in libmigo'
  END AS component
FROM live l LEFT JOIN site s ON s.leaf = l.callsite_id;

SELECT '== total live bytes' AS section, printf('%.2f MiB', SUM(bytes) / 1048576.0) AS v, '' AS w FROM attributed
UNION ALL
SELECT '== by component', component, printf('%8.2f MiB  %5.1f%%', SUM(bytes) / 1048576.0,
       100.0 * SUM(bytes) / (SELECT SUM(bytes) FROM attributed))
FROM attributed GROUP BY component
UNION ALL
SELECT * FROM (
  SELECT '== top sites', printf('%7.0f KiB  %s', SUM(bytes) / 1024.0, component), substr(fn, 1, 160)
  FROM attributed GROUP BY fn ORDER BY SUM(bytes) DESC LIMIT 60
);
