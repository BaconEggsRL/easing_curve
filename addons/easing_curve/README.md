# <img src="https://raw.githubusercontent.com/BaconEggsRL/easing_curve/refs/heads/master/media/icon_32x32.png"> Easing Curve
GDScript curve editor for easing functions.

Designed for parity with Godot's Tween system and easing equations.

* [Robert Pennner's easing functions](https://easings.net) (GDScript port: [godot-easing](https://github.com/impmja/godot-easing))
* [Godot 4.6 easing equations](https://github.com/godotengine/godot/blob/4.6/scene/animation/easing_equations.h)
* Includes some unique [CSS](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Values/easing-function/cubic-bezier) and [JS](https://animejs.com/documentation/easings/built-in-eases/) easing functions.

**&nbsp;**

<!--- ![easing_curve.png](https://github.com/BaconEggsRL/easing_curve/blob/master/media/easing_curve.png) --->

![preset_example.gif](https://raw.githubusercontent.com/BaconEggsRL/easing_curve/refs/heads/master/media/preset_example.gif)

**&nbsp;**

# User Guide

### Compatibility:

* Godot 4.4.0 is the verified minimum for plugin loading.
* The full workflow has been verified on Godot 4.7.1.

### Installation:

* Copy `addons/easing_curve/` into your project's `addons/` folder.
* Enable **Easing Curve** through **Project > Project Settings > Plugins**.

### Create a new EasingCurve:

 * Export a variable of type EasingCurve, and create a new EasingCurve resource.
  * The resource will pre-populate with a linear cubic_bezier curve

**&nbsp;**


Select a Curve Preset:
---

* Select the **Ease** and **Trans** option buttons to choose from a variety of pre-made curve presets.
* These presets mimic the behavior of Godot's Tween system (See test_scene/test.tscn to compare.)
* New function presets not found in the built-in Tween system include:
  * **Jitter** -- Noisy linear interpolation
  * **Irregular** -- Stepwise linear with randomness
  * **Step** -- Stepwise function
  * **Power** -- Fractional power function
* The plugin also takes existing presets from the Tween class and adds additional functionality:
  * **Elastic** -- Specify a custom amplitude and period
  * More features planned for Bounce, Back, and Spring functions.

**&nbsp;**

Adjust your curve using the Curve Editor:
---

Bézier-backed presets, including multi-segment presets, expose all points and handles in the curve editor.

* **Add and Remove Points**
  * Left click anywhere on the grid to add a new point, or click the "Add Point" button.
  * Right click a point to delete it, or click the trash button icon in the points list.

* **Adjust the Control Points**
  * You can adjust the bezier curve control points by dragging with the mouse or editing the points list.
  * Control handles can be moved outside the grid box, but point positions cannot.

* **Locking Control Points**
  * Vector2 properties can be locked by clicking the lock icon.
  * Locked properties cannot be changed, except by copy-paste. This can be used to drag a point without affecting its control handles.

* **Zoom and Pan**
  * Zoom and pan can be used to see points outside the grid box. The grid box represents an x_range and y_range of 0 to 1.
  * Use the zoom slider or scroll wheel to adjust the zoom level. The arrow box to the right of the zoom slider will reset the zoom.
  * Click and drag with the middle mouse button to pan the curve editor. The arrow box to the right of the zoom slider will reset the pan.

* **Reordering the Points List**
  * Click the up or down arrows or drag a point in the points list to swap it with another point.
  * You can also use the drag handles to move a point anywhere in the points list.
  * Select a property of any point and right click to copy / paste.

**&nbsp;**

### Save your custom EasingCurve:

* The curve editor allows you to start from a basic preset and modify to suit your needs.
* When you're happy with your custom curve, you can save the resource to use wherever you want.
* Use the "Make Unique" option on saved resources to avoid modifying the original resource.
* Refer to the presets folder for some examples and try them out in the provided test scene.

### Resource Autosaving

* Godot automatically saves changes made to saved resources. This is the same behavior as the built-in `Curve` resource.
* If you edit an Easing Curve that has been saved as a resource, those changes will persist. Only modify a saved resource when you intend to keep the changes; otherwise, you may need to undo them.

### Runtime updates:

* Any changes you make to the curve take effect immediately at runtime in the test scene--even when modifying in the local scene tree.
* See how your changes affect the scene in real time. A restart button is provided in the top-right corner as a fallback.

**&nbsp;**


### **Future feature map:**

---

* Handle mode support akin to AnimationPlayer (Free, Linear, Balanced, Mirrored)

**&nbsp;**


### Thank you!

---

Thank you for using the EasingCurve plugin.
Please support the development by sharing, starring or commenting if you found it useful.

This is my first plugin, so please feel free to submit an issue or PR if you find anything that needs fixing.

You can find all my addons on my [GitHub profile page](https://github.com/BaconEggsRL/).

<a href='https://ko-fi.com/baconeggsrl' target='_blank'><img height='36' style='border:0px;height:36px;' src='https://cdn.ko-fi.com/cdn/kofi1.png?v=3' border='0' alt='Buy Me a Coffee at ko-fi.com' /></a>


### AI Usage Disclaimer:
AI-assisted coding was used during development for implementation, debugging, refactoring, and release-readiness review. Generated suggestions and changes were reviewed, modified where needed, and tested in Godot before release.

### License:
Released under the [MIT License](LICENSE.md).
