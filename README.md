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
- Desktop with OpenGL (Win/Linux/OSX) or DirectX (Windows only)
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
- For [HashLink](https://github.com/NMB-Team/hashlink-nmb): run `haxe [sample]_hl.hxml` then run `hl <sample>.hl` to run
- For Consoles, contact us: nicolas@haxe.org

HashLink graphics backends
--------------------------

HashLink Lumen builds use `-lib limen`. Enable the graphics backends that should be compiled into the build with these defines:

```hxml
-D gfx_dx11
-D gfx_dx12
-D gfx_vulkan
-D gfx_opengl
```

Only compiled backends can be selected at runtime. A full Windows Lumen build can include all of them:

```hxml
-lib limen
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
