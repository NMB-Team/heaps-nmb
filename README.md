<div align=center>

[![Heaps.io logo](https://raw.githubusercontent.com/HeapsIO/heaps.io/master/assets/logo/logo-heaps-color.png)](http://heaps.io)

# Heaps NMB
_High Performance Game Framework_

[![Build Status](https://github.com/NMB-Team/hashlink-nmb/workflows/Build/badge.svg "GitHub Actions")](https://github.com/NMB-Team/heaps-nmb/actions?query=workflow%3ACI)
[![](https://img.shields.io/discord/162395145352904705.svg?logo=discord)](https://discordapp.com/invite/sWCGm33)

</div>

**Heaps** is a cross platform graphics engine designed for high performance games. It's designed to leverage modern GPUs that are commonly available on desktop, mobile and consoles.

Heaps is currently working on:
- HTML5 (requires WebGL)
- Mobile (iOS, tvOS and Android)
- Desktop with OpenGL/Vulkan (Win/Linux/OSX) or Direct3D 11/12 (Windows only)
- Consoles (Nintendo Switch, Sony PS4, XBox One - requires being a registered developer)

Community
---------

Ask questions or discuss on <https://community.heaps.io>

Chat on Discord <https://discord.gg/sWCGm33> or Gitter <https://gitter.im/heapsio/Lobby>

Samples
-------

In order to compile the samples, go to the `samples` directory and run `haxe gen.hxml`, this will generate a `build` directory containing project files for all samples.

To compile:
- For JS/WebGL: run `haxe [sample]_js.hxml`, then open `index.html` to run
- For [HashLink](https://github.com/NMB-Team/hashlink-nmb), compile the generated
  `[sample]_hl.hxml` (OpenGL), `[sample]_hlvulkan.hxml`, `[sample]_hldx11.hxml`,
  or `[sample]_hldx12.hxml`, then run the resulting `.hl` file with `hl`.
- For Consoles, contact us: nicolas@haxe.org

HashLink graphics backends
--------------------------

HashLink-NMB builds use the current [Limen](https://github.com/NMB-Team/Limen)
API, including `limen.Window` and backend packages such as `limen.vulkan`.
Register a local checkout with `haxelib dev limen /path/to/Limen` and build
against the native binaries from the same revision.

Enable the graphics backends that should be compiled into the build with these defines:

```hxml
-D gfx_dx11
-D gfx_dx12
-D gfx_vulkan
-D gfx_opengl
```

Only compiled backends can be selected at runtime. A full Windows Limen build can include all of them:

```hxml
-lib limen
-D hl-ver=1.15.0
-D gfx_dx11
-D gfx_dx12
-D gfx_vulkan
-D gfx_opengl
```

To choose the default backend for `hxd.GraphicsDriverConfig`, add one default define:

```hxml
-D default_gfx_dx11
-D default_gfx_dx12
-D default_gfx_vulkan
-D default_gfx_opengl
```

If no `default_gfx_*` define is set, the default order is:

```text
gfx_dx12 -> gfx_dx11 -> gfx_vulkan -> OpenGL
```

OpenGL is used when no explicit backend define is provided, or when `gfx_opengl` is the selected/default backend.

Project files for [Visual Studio Code](https://code.visualstudio.com/) are also generated.

Get started!
------------
* [Installation](https://heaps.io/documentation/installation.html)
* [Live samples with source code](https://heaps.io/samples/)
* [Documentation](https://heaps.io/documentation/home.html)
* [API documentation](https://heaps.io/api/)

### JavaScript DX12 host

The `-D dx12` JavaScript target uses the Origin DX12 host API through
`h3d.impl.driver.dx12.js.JSDriver`. It requires the host's `dx.*` bindings and
JavaScript implementations of `hl.*`; it does not run in a standard browser.
Supply those bindings on the compiler classpath. Regular JavaScript builds
continue to use WebGL, and native builds use Limen's selected graphics driver.

### Explicit render graphs

`h3d.RenderGraph` is an opt-in scheduler for Engine render callbacks.
Create one graph per reusable set of passes, declare each pass once, then
call `execute()` from the normal render callback.

```haxe
final graph = new h3d.RenderGraph(engine);
final source = graph.transientTarget(256, 256);
final destination = graph.importTexture(output);
final copy = new h3d.pass.Copy();

graph.addColorPass("clear source", source, 0xFF438BDA);
final pass = graph.addColorPass("copy to output", destination, 0,
    (_, g) -> copy.apply(g.texture(source), null));
graph.use(pass, source, Read, 0, 0);

// inside the render callback
graph.execute();
```

`addColorPass` declares a color attachment and optionally clears it.
`addPass` records custom work through the existing Engine and driver APIs.
Declare full replacements as `Write` and partial updates as `ReadWrite`.
Use `dependsOn` for ordering dependencies that declarations cannot
express. Mark observable work with `sideEffect` and callbacks with
unknown resource usage as `external`. Keep callbacks on the render thread
and balance any target pushes they make.

Import persistent and history textures and buffers explicitly. Rebind a
texture import between executions to replace its backing object, including
when replacing a history texture. Use `swapTextures()` for two imports that
exchange roles. The graph resolves imported texture
objects on each execution. Use `backBuffer()` for the current swapchain
color attachment. Use `reset()` when rebuilding the graph and `dispose()`
to release its owned transient targets. Imported objects remain owned by the
caller.

Transient targets are single-sample color textures initialized by a full
clear. The optional `aliasTargets` constructor argument lets disjoint,
compatible lifetimes share a physical texture. Resolve graph textures inside
the active pass and release references to transient textures when it ends.
Custom and opaque work uses conservative boundaries. For API-specific
depth, stencil, MRT, or transfer operations use a custom pass and the
existing driver capabilities.

Native Direct3D 12 color passes can declare reads from subresources
disjoint from the active color attachment. Declarations must match the
bound view. A sampled view starting at a mip includes all remaining
resident mips of that view. Direct3D 11 keeps separate transient targets
when aliasing is requested.
