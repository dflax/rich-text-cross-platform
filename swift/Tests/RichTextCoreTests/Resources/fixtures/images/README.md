# Fixture images

The actual image bytes behind the object keys the Delta fixtures reference. Checked in so the
B2 bucket's contents are reproducible and so `LocalDirectoryImageFetcher` can serve real
content with no network at all.

Filenames here replace `/` with `_`, which is the mapping `LocalDirectoryImageFetcher` uses:
`doc-images/map.jpg` on B2 is `doc-images_map.jpg` here.

| File | Object key | Referenced by |
|---|---|---|
| `doc-images_8f2a0c11.jpg` | `doc-images/8f2a0c11.jpg` | `image-only`, `image-with-alt`, `full-vocabulary` |
| `doc-images_map.jpg` | `doc-images/map.jpg` | `leading-image`, `trailing-image` |
| `doc-images_first.jpg` | `doc-images/first.jpg` | `adjacent-images` |
| `doc-images_second.jpg` | `doc-images/second.jpg` | `adjacent-images` |
| `doc-images_lane-diagram.jpg` | `doc-images/lane-diagram.jpg` | `image-in-bulleted-region` |

Each is a solid colour with its name drawn across it, 1200x800, JPEG q0.8 — deliberately
distinguishable at a glance, because the P1 side-by-side comparison and the P7 cross-platform
pass both come down to telling one image from another in a screenshot.

## Regenerating and re-uploading

    swift generate.swift .
    for f in *.jpg; do b2 file upload --content-type image/jpeg rich-text-poc "$f" "${f//_//}"; done

Verify one landed and is publicly readable:

    curl -I 'https://f005.backblazeb2.com/file/rich-text-poc/doc-images/map.jpg'   # expect 200
