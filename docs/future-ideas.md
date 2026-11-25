# Future ideas

Ideas that have been discussed but not decided. Nothing here is planned work. (The second idea on this
page has since been built; its section says how.)

## A third look: "Reimagined"

Raised 2026-11-14. Each scene currently has two looks: Modern (the same picture, drawn sharply and
smoothly) and 1993 (the original pixels). A third look would re-imagine each scene using graphics features
that did not exist in 1993. It would be one more choice in the look switch.

**Status: undecided.** Each scene is to be considered on its own, and only done if the result would
genuinely add to the project. Some scenes may not be improved by it at all.

### The principle

Keep each scene's motion and character recognisable, and change how light behaves. Every 1993 scene was
flat colour looked up in a table. Light can now glow, bounce, bend, scatter and cast shadows.

### What makes it possible

- **Brightness beyond white.** Current Mac displays can show highlights several times brighter than a white
  page (Apple calls this EDR). Lights can dazzle instead of being a flat white patch.
- **Ray tracing.** Following rays of light as they reflect and refract: true reflections, glass, soft shadows.
- **Simulation on the graphics chip.** Millions of particles, or a grid of fluid, moved by physics each frame.
- **Camera effects.** Focus, motion blur, lens glow, film grain.
- **Fog and haze.** Light scattering in the air: beams, depth, atmosphere.

### First thoughts, scene by scene

| Scene | Idea |
|---|---|
| Dot Tunnel | Each dot a tiny light in faint haze, casting beams and glow. A million dots, streaking with motion blur, the far end fading into fog. |
| Rings | Ripples on a dark pool seen at a low angle: real waves catching reflections and throwing wavering light on the floor beneath. |
| Interference | Two disturbances in that same pool. The pattern is what real overlapping waves do, so it would come from physics instead of two pictures. Seen from above through the water. |
| Techno Bars | Neon tubes spinning in a dark room with a polished floor. Trails become true motion blur and afterglow; on each beat the tubes flare and light the room. |
| Bouncing Dots | Glass marbles on a wet reflective floor: refraction, soft shadows that sharpen near the ground, small bright spots of focused light, shallow focus. |
| Plasma | A real fluid (ink in water, a gas giant's surface) simulated so colours swirl and mix. Or an aurora in a night sky. |
| Hidden Starfield | A flight through a galaxy: millions of stars coloured by temperature, dust lanes, glowing gas clouds, bright stars that bloom. |
| 3D Sine Landscape | The same hills at dusk with a real atmosphere: low sun, long shadows, mist in the valleys, the dark red valley as a river catching the light. |
| Plasma Cube | A cube of glass with the plasma glowing inside it, refracting through the edges and lighting the surface it flies over. |

### Cautions

- **Taste matters more than technology.** It is easy to pile on effects until a scene is unrecognisable.
- **Some scenes are abstract by nature.** The techno bars and the plasma were never pictures of anything;
  giving them a physical setting is an invention. Those two are the most open.
- **Effort varies widely.** Glow, haze and brightness are cheap and would transform the tunnel, starfield
  and bars. Fluid simulation and ray-traced glass are substantial projects.
- **Nothing to test against.** The self-test cannot judge this look; the eye is the only check.

### If it is tried

Start with the Dot Tunnel. It needs only glow, haze and bright output, the cheapest ingredients, so it would
show quickly whether the direction is worth pursuing. The shared pieces built for it would be reused by
most other scenes. Best done after the remaining planned scenes and the code review.

## The whole demo, in the modern look

Raised 2026-11-14. With the ships and the city done (2026-11-14), the app holds 12 of the demo's roughly 23
effects. The user's view: the existing complete port is the original code at the original resolution, so
the whole demo redrawn in the modern look, with music, would be something that does not yet exist.

**Status: BUILT, 2026-11-24/25, as Play Demo** (see [demo-timeline.md](demo-timeline.md)). All 19 parts run
in order with the music; 17 are scenes with both looks; the opening credits and the credits are still to
come. It was done differently from the plan below in two ways: the music is the original tracker songs
played live by libopenmpt (not rendered to audio beforehand), because the parts synchronised on the
music's live position; and the pictures are scaled by Super-xBR on the graphics chip (no AI upscaling).
The rest of this section is the plan as first written, kept for the record.

### The pieces, in suggested order (as planned 2026-11-14)

1. **Music.** Render the two tracker songs (`MAIN/MUSIC0.S3M`, `MAIN/MUSIC1.S3M` in the original source)
   to ordinary audio once, with a tool built on libopenmpt, and play them with what macOS provides (no new
   dependencies). Make a timing table at the same time giving the second at which each section ("order")
   of each song starts, so the app can tell where the music is from the clock, and so that choosing a scene
   starts the music at that scene's section. Each scene's song and starting section are known. First
   benefit: the Techno Bars flash on the real beat instead of the estimated one.
   To confirm before the repository is made public: that the songs are covered by the same public-domain
   release as the code.
2. **Picture-based scenes**, with the 1993 look using the original pictures and the modern look using
   the original pictures through a pixel-art scaler (Super-xBR, built 2026-11-24), or re-made from source where possible (the user
   decided against AI-upscaled artwork, 2026-11-24). About eleven: opening credits, explosion, title picture, the picture with
   the TV switch-off, mountain scroller, lens, rotozoomer, water scroller, jelly logo, end picture, credits,
   end scroller. Most are small; the lens and rotozoomer have the most substance.
3. **A "play the demo" mode**: every scene in order, timed to the music, with the original lead-ins and
   transitions (which the standalone scenes deliberately leave out) restored as an option.

### Notes on scaling up the artwork

- The originals are in old formats (LBM, and the demo's own); they can be converted to PNG with correct
  colours for the user to work from.
- 320x200 pixels were not square. Each picture filled a 4:3 screen, so the upscale must also correct the
  shape.
- With 256 colours the artists faked smooth shading with fine dot patterns (dithering). Upscalers made for
  photographs tend to smear these; tools made for pixel art, or a light smoothing pass first, usually do
  better. Expect to experiment per picture.
- Some scenes do more than show a picture (the lens tints and bends what is beneath it using palette
  tricks). In the modern look those become real tinting and distortion in a shader.
- Large picture files need the app to carry data files; see how the VISU engine work handles resources.
