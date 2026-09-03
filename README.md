# <img src="https://raw.githubusercontent.com/BaconEggsRL/easing_curve/refs/heads/master/media/icon_32x32.png"> Easing Curve
GDScript curve editor for easing functions.

Designed for parity with Godot's Tween system and easing equations.

The `native-v2-spike` branch also contains the experimental
`NativeEasingCurve` and `NativeEasingCurvePoint` GDExtension APIs. They are
independent from `EasingCurve` and `EasingCurvePoint`, and both API families can
coexist in one project. The GDScript API remains the supported legacy/fallback
API and is **not deprecated**. Deprecation can be considered only after the
Native implementation meets or exceeds the legacy runtime, editor,
serialization, compatibility, platform, reliability, and performance gates;
removal would require a separate future plan.

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

#### Godot Asset Library / Asset Store

**Godot 4.7 and newer:**
* Install **Easing Curve** normally through the Asset Store.
* The plugin should be installed to `res://addons/easing_curve/`.

**Godot 4.4–4.6:**
* Download **Easing Curve** through the Asset Library.
* In the **Configure Asset Before Installing** window, make sure **Ignore asset root** is **unchecked** before installing.
* Confirm that the installation preview shows the plugin under:
  `res://addons/easing_curve/`
* Complete the installation.

#### Manual Installation

* Copy `addons/easing_curve/` into your project's `addons/` folder.
* The resulting path should be:
  `res://addons/easing_curve/`

#### Enable the Plugin

* Open **Project > Project Settings > Plugins**.
* Enable **Easing Curve**.

### Create a new EasingCurve:

 * Export a variable of type EasingCurve, and create a new EasingCurve resource.
  * The resource will pre-populate with a linear cubic_bezier curve.

**&nbsp;**


Select a Curve Preset:
---

Select the **Ease** and **Transition** options to choose from the built-in presets and additional easing functions.

#### Ease Modes

All supported transitions can use the following ease modes.
Custom, Linear, Constant, and CSS transitions do not have selectable ease modes.
Ease modes control **where the easing effect is applied** over the duration of the curve:

* **In** -- Starts slow and ends fast.
* **Out** -- Starts fast and ends slow.
* **In Out** -- Starts slow, speeds up towards the middle, and slows down at the end.
* **Out In** -- Starts fast, slows down towards the middle, and speeds up at the end.

The exact shape and behavior depend on the selected **Transition**.
For example, an Elastic or Bounce transition may oscillate or overshoot rather than simply accelerate or decelerate.

#### Godot Tween Transitions

These transitions are designed for parity with Godot's built-in Tween easing behavior:

* **Linear** -- Linear interpolation, [Bézier]
* **Sine** -- Sinusoidal easing, [Bézier]
* **Quad** -- Quadratic easing, [Bézier]
* **Cubic** -- Cubic easing, [Bézier]
* **Quart** -- Quartic easing, [Bézier]
* **Quint** -- Quintic easing, [Bézier]
* **Expo** -- Exponential easing, [Bézier]
* **Circ** -- Circular easing, [Bézier]
* **Back** -- Back easing, configurable **Overshoot**, [Bézier]
* **Elastic** -- Elastic oscillation, configurable **Amplitude** and **Period**, [Function]
* **Bounce** -- Bouncing motion, configurable **Number of Bounces** and **Bounce Damping**, [Function]
* **Spring** -- Spring-like oscillation, configurable **Frequency** and **Decay**, [Function]

Bézier-backed presets can be edited directly in the curve editor.
Modifying a preset creates a customized version while retaining the original transition and ease selection.

#### Additional Transitions

Easing Curve also includes transitions beyond Godot's built-in Tween system:

* **Constant** -- Returns a configurable **Constant Value**, [Bézier]
* **Physics Spring** -- Spring easing using physics (**Stiffness**, **Damping**, **Mass**, and **Velocity**), [Function]
* **Jitter** -- Stronger persistent-amplitude random variation; more points primarily increase jitter frequency (**Num Points**, **Randomness**) and **Generate Tool Button**, [Function]
* **Irregular** -- Noisy linear interpolation whose deviations shrink with more points / lower randomness (**Num Points**, **Randomness**) and **Generate Tool Button**, [Function]
* **Step** -- Staircase easing (**Steps**, **From Start**, and **Y Offset**), [Function]
* **Power** -- Fractional power easing (**Power**), [Function]

CSS easing functions can also be used directly:

* **Cubic Bézier** -- Define a CSS-style `cubic-bezier()` easing curve, [Function]
* **Linear** -- Define a CSS-style `linear()` easing function with custom stops, [Function]


**&nbsp;**
Adjust your curve using the Curve Editor:
---

Bézier-backed presets, including multi-segment presets, expose all points and handles in the curve editor.

* **Adding and Removing Points**
  * Left click anywhere on the grid to add a new point, or click the "Add Point" button.
  * Right click a point to delete it, hold right click and drag across points to remove them, or click the trash button icon in the points list.

* **Adjusting the Control Points**
  * You can adjust the bezier curve control points by dragging with the mouse or editing the points list.
  * Control handles can be moved outside the grid box, but point positions cannot.

* **Locking Control Points**
  * Vector2 properties can be locked by clicking the lock icon.
	* Locked properties cannot be changed (except by copy-paste or manual re-ordering of the points list.)
	* Locking a point's controls (left or right) allows you to drag the point without affecting its control handles.
  * Lockable properties include point position, left control position, and right control position.
	* Force Linear and Lock control states are available in Free and Linked handle modes.

* **Handle Modes**
  * Each point can use a handle mode to control how its left and right control handles behave:
		* **Free** -- Each handle moves independently without affecting the other handle.
		* **Linear** -- Keeps the handles aligned with the neighboring points, creating straight-line segments through the point.
		* **Balanced** -- Keeps both handles aligned in opposite directions while allowing each handle to have a different length.
		* **Mirrored** -- Keeps both handles aligned in opposite directions and at the same length. Moving one handle mirrors the other across the point.
		* **Linked** -- Keeps both controls at a shared position.
	* Note that control Locked and Forced Linear states apply in Free and Linked modes, and are preserved when switching modes.
  * The selected-point toolbar shows the point number, Handle Mode, L/R control state, and Reset controls.

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

* TBD — open to suggestions!
* Found a bug? Please open a [Bug Report](https://github.com/BaconEggsRL/easing_curve/issues/new?template=bug_report.yml).
* Have an idea for a new feature or improvement? Open a [Feature Request](https://github.com/BaconEggsRL/easing_curve/issues/new?template=feature_request.yml).
* Contributions are welcome! Feel free to open a [Pull Request](https://github.com/BaconEggsRL/easing_curve/pulls).

**&nbsp;**


### Thank you!

---

Thank you for using the EasingCurve plugin.
Please support the development by sharing, starring or commenting if you found it useful.

This is my first plugin, so feedback and contributions are always welcome.
See the links above to report bugs, suggest features, or contribute changes.

You can find all my addons on my [GitHub profile page](https://github.com/BaconEggsRL/).

<a href='https://ko-fi.com/baconeggsrl' target='_blank'><img height='36' style='border:0px;height:36px;' src='https://cdn.ko-fi.com/cdn/kofi1.png?v=3' border='0' alt='Buy Me a Coffee at ko-fi.com' /></a>


### AI Usage Disclaimer:
AI-assisted coding was used during development for implementation, debugging, refactoring, and release-readiness review. Generated suggestions and changes were reviewed, modified where needed, and tested in Godot before release.

### License:
Released under the [MIT License](LICENSE.md).


---

## Star History

<a href="https://www.star-history.com/?repos=BaconEggsRL%2Feasing_curve&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=BaconEggsRL/easing_curve&type=date&theme=dark&legend=top-left&sealed_token=nRCgB2qxeEZVuTnXUrEG2QDyqIe13lbLuZpAr-G3LQ1bI1ePPeXCqFTMQLOMrcLJOt51N_U5Z1TwHPwpXhce4XuNB4g4ryA4xsPFDi9VS7DFDTVH412M0efFVQpEoq6IotFCRdS21ATJ4SvrEu6p4JY23FgCvQWg9ST4142oJhs7baKam4lmHB8fOguf" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=BaconEggsRL/easing_curve&type=date&legend=top-left&sealed_token=nRCgB2qxeEZVuTnXUrEG2QDyqIe13lbLuZpAr-G3LQ1bI1ePPeXCqFTMQLOMrcLJOt51N_U5Z1TwHPwpXhce4XuNB4g4ryA4xsPFDi9VS7DFDTVH412M0efFVQpEoq6IotFCRdS21ATJ4SvrEu6p4JY23FgCvQWg9ST4142oJhs7baKam4lmHB8fOguf" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=BaconEggsRL/easing_curve&type=date&legend=top-left&sealed_token=nRCgB2qxeEZVuTnXUrEG2QDyqIe13lbLuZpAr-G3LQ1bI1ePPeXCqFTMQLOMrcLJOt51N_U5Z1TwHPwpXhce4XuNB4g4ryA4xsPFDi9VS7DFDTVH412M0efFVQpEoq6IotFCRdS21ATJ4SvrEu6p4JY23FgCvQWg9ST4142oJhs7baKam4lmHB8fOguf" />
 </picture>
</a>
