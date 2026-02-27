# EasingCurve
GDScript curve editor for easing functions.

Designed for parity with Godot's Tween system and easing equations.

* [Robert Pennner's easing functions](https://easings.net) (GDScript port: [godot-easing](https://github.com/impmja/godot-easing))
* [Godot 4.6 easing equations](https://github.com/godotengine/godot/blob/4.6/scene/animation/easing_equations.h)
* Includes some unique [CSS](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Values/easing-function/cubic-bezier) and [JS](https://animejs.com/documentation/easings/built-in-eases/) easing functions.

**&nbsp;**

<!--- ![easing_curve.png](https://github.com/BaconEggsRL/easing_curve/blob/master/screenshots/easing_curve.png) --->

![preset_example.gif](https://github.com/BaconEggsRL/easing_curve/blob/master/screenshots/preset_example.gif)

**&nbsp;**

# User Guide



### Create a new EasingCurve:

 * Export a variable of type EasingCurve, and create a new EasingCurve resource.
  * The resource will pre-populate with a linear cubic_bezier curve.

**&nbsp;**

### Select a Curve Preset:

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

### Adjust your curve using the Curve Editor:

Bezier curve points can be modified in the curve editor. This is supported on any preset generated using the cubic_bezier function.

* **Add and Remove Points**
  * Left click anywhere on the grid to add a new point, or click the "Add Point" button.
  * Right click a point to delete it, or click the trash button icon in the points list.
  
* **Adjust the Control Points**
  * You can adjust the bezier curve control points by dragging with the mouse or editing the points list.
  * Control handles can be moved outside the grid box, but point positions cannot.


* **Locking Control Points**
  * Vector2 properties can be locked by clicking the lock icon.
  * Locked properties cannot be changed. This can be used to drag a point without affecting its control handles.
  
* **Zoom and Pan**
  * Zoom and pan can be used to see points outside the grid box. The grid box represents an x_range and y_range of 0 to 1.
  * Use the zoom slider or scroll wheel to adjust the zoom level. The arrow box to the right of the zoom slider will reset the zoom.
  * Click and drag with the middle mouse button to pan the curve editor. The arrow box to the right of the zoom slider will reset the pan.
  
* **Reordering the Points List**

  * Click the up or down arrows or drag a point in the points list to swap it with another point.
  

**&nbsp;**

### Save your custom EasingCurve:

* The curve editor allows you to start from a basic preset and modify to suit your needs.
* When you're happy with your custom curve, you can save the resource to use wherever you want.
  * **NOTE:** Making an EasingCurve resource unique WILL crash the editor.
  * It is recommended to first save your custom resource, then duplicate it in the FileSystem dock.

* Refer to the presets folder for some examples and try them out in the test scene.

**&nbsp;**

### **Known Issues**

---

* Making the resource unique will crash the editor.
* Runtime updating of curves is not fully supported (works on some modes, but not on others.) This is partially due to a Godot Engine bug regarding Arrays of type Resource which will hopefully be fixed soon (https://github.com/godotengine/godot/issues/101979).
* Minor differences between cubic_bezier and Godot's built-in Tweens for some functions. This is likely due to some errors in the sampling function; in the future will implement some sample_baked methods like Godot's built-in Curve resource.
* Undo / Redo not fully implemented.

**&nbsp;**

### **Future feature map**

---

* Handle mode support akin to AnimationPlayer (Free, Linear, Balanced, Mirrored)
* Additional function options (CSS linear(), Back overshoot parameter, Spring stiffness & damping)

**&nbsp;**

### Thank you!

---

Thank you for using the EasingCurve plugin.
Please support the development by sharing, starring or commenting if you found it useful.  

This is my first plugin, so please feel free to submit an issue or PR if you find anything that needs fixing.

You can find all my addons on my [GitHub profile page](https://github.com/BaconEggsRL/).

<a href='https://ko-fi.com/baconeggsrl' target='_blank'><img height='36' style='border:0px;height:36px;' src='https://cdn.ko-fi.com/cdn/kofi1.png?v=3' border='0' alt='Buy Me a Coffee at ko-fi.com' /></a>
