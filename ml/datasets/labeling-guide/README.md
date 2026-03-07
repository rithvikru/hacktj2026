# Labeling Guide

Follow these rules for every annotation task.

## Object Identity

1. Annotate the object instance, not the support surface.
2. Use the canonical label from `datasets/manifests/closed-set-labels.yaml`.
3. Map user-facing `AirPods` queries to `airpods_case` unless a signal-backed tag exists.

## Visibility

Use exactly one visibility state:

1. `fully_visible`
2. `partially_occluded`
3. `soft_hidden`
4. `hard_hidden`
5. `inside_container`
6. `offscreen`
7. `removed`

## Boxes and Masks

1. Draw a box tightly around the visible object extent.
2. If a mask is provided, keep it inside the image bounds and aligned to the visible pixels.
3. Do not annotate guessed pixels hidden behind an occluder in the visible detection set.

## Support and Containment

Record these fields whenever they are known:

1. `support_surface`
2. `container`
3. `nearest_furniture`
4. `room_section`

## Hidden Data

For hidden-object episodes:

1. record the last visible frame
2. record the final hidden state
3. record the true final container or support surface
4. preserve candidate regions even when the true location is unknown at annotation time
