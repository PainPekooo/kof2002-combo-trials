# KOF 2002 Combo Trials

> ⚠️ **FASE BETA.** Los combos **no están probados en el juego real con todos los personajes**. Muchos salieron de la wiki de 2002 UM y de listas de movimientos, así que algunos pueden no salir en KOF 2002. Si encuentras uno que no funciona, [abre un issue](../../issues) o corrígelo (ver [Agregar o corregir combos](#agregar-o-corregir-combos)).

Modo **Combo Trials** para *The King of Fighters 2002* (`kof2002`) en **Fightcade / FBNeo**, como el de los juegos de pelea modernos. Eliges un combo, aparecen los inputs en pantalla con flechas y botones, y la barra te marca paso a paso si lo estás haciendo bien. Si fallas un paso, se reinicia.

*English summary below.*

## Qué tiene

- **43 personajes, 174 combos** de 0 a 3 barras, incluidos los ocultos (Kusanagi y los Orochi).
- **Flechas de palanca y botones de colores**, como en KOF (A rojo, B amarillo, C verde, D azul). Las flechas se voltean solas según el lado de la pantalla.
- **Verificación real de inputs:** movimientos (qcf, dp, hcb, qcfx2…), cargas ([2]8, [4]6), botones simultáneos (BC, AC) y correr, más el **contador de golpes** del juego para saber si el combo se cortó.
- **Modo rekka** (por ahora Kim): cadenas como Sanren Geki y Sankuu Kyaku. Cada parte exige su propio movimiento.
- **Contador de repeticiones:** hasta 10 por combo (`x3/10`).
- **Barra compacta** o **panel completo** con el nombre de cada movimiento y el motivo del error.
- Se carga solo como **addon del training mode** de Fightcade ([fbneo-training-mode](https://github.com/peon2/fbneo-training-mode)).

## Instalación

### Como addon del training mode (recomendado)

Así se carga solo cada vez que abres KOF 2002 en **Training** desde Fightcade.

1. Busca la carpeta del training mode de KOF 2002:
   - **Windows:** `Fightcade\emulator\fbneo\fbneo-training-mode\games\kof2002\`
   - **Linux (Flatpak):** `~/.var/app/com.fightcade.Fightcade/data/fbneo-training-mode/games/kof2002/`
   - **Linux (descarga normal):** `Fightcade/emulator/fbneo/fbneo-training-mode/games/kof2002/`
2. Crea dentro una carpeta `addon`.
3. Copia ahí `kof2002_combo_trials.lua` y un archivo `addons.lua` con este contenido:
   ```lua
   addons_run = {
   	"kof2002_combo_trials.lua",
   }
   ```
4. Abre KOF 2002 en Training. La barra aparece arriba.

### A mano

En FBNeo: *Game → Lua Scripting → New Lua Script Window → Browse*, elige `kof2002_combo_trials.lua` y pulsa **Run**.

> **Linux con Flatpak:** Fightcade no puede leer archivos fuera de su carpeta. Copia el script a `~/.var/app/com.fightcade.Fightcade/data/` y en la ventana de Lua escribe solo el nombre del archivo.

## Controles

Juega en el lado **P1**. Todos los controles se usan **manteniendo Start**:

| Botones | Acción |
|---|---|
| Start + ↑ / ↓ | Cambiar personaje (orden alfabético) |
| Start + ← / → | Cambiar combo |
| Start + A | Combos ↔ rekkas (solo personajes con rekkas) |
| Start + C | Modo compacto → completo → oculto |
| Start + D | Reiniciar el intento |

Si lo cargas a mano (sin el training mode), también funciona **Coin** en lugar de Start. Con el training mode, Coin abre su propio menú.

**Colores de la barra:** 🟡 amarillo = el paso que te toca · 🟢 verde = bien hecho · 🔴 rojo = donde fallaste. Una flecha dentro de un recuadro significa **mantener** esa dirección (carga).

## Detección del personaje

No hay una dirección de memoria pública para saber con qué personaje juega P1 en KOF 2002, así que el script **la aprende**:

1. Al principio elige el personaje a mano (Start + ↑/↓). El script recuerda el último que usaste.
2. Cada vez que logras un combo guarda una foto de la memoria del jugador.
3. Después de lograr combos con **3 o 4 personajes distintos**, encuentra el dato del personaje, muestra *"Ya reconozco a los personajes solo"* y desde ahí cambia la lista automáticamente.

Lo aprendido se guarda en `kof2002_combo_trials_datos.txt`. Si encuentras la dirección (sale en la consola de Lua como *"Personaje detectado en 0x…"*), compártela en un issue y la dejamos fija para todos.

## Estado de los combos

| Origen | Personajes |
|---|---|
| Página de KOF 2002 en Dream Cancel (más confiable) | Kim, Daimon, Ralf, Clark, Choi, Mature, Vice, Yashiro, Chris, Kula, Kusanagi, O.Yashiro, O.Shermie |
| Combos de 2002 UM, filtrados a movimientos que existen en 2002 | La mayoría del resto |
| Armados a partir de la lista de movimientos (sin fuente) | Algunos de Joe, Leona, K9999, O.Chris, Mai, Athena y rekkas 4 y 5 de Kim |

**Probados en el juego real:** solo parte de los de Kim. Se agradecen reportes de qué combos salen y cuáles no.

## Agregar o corregir combos

Los combos están al principio del script, en la tabla `CHARS`. Cada combo es una línea:

```lua
{ name = "Terry", combos = {
	{ 0, "cl.C, qcb+A:Burn Knuckle" },          -- { barras, "pasos" }
	{ 1, "cl.C, qcb hcf+A:Power Geyser" },
}},
```

Los pasos van separados por coma; `:Nombre` al final de un paso es opcional.

| Notación | Significa |
|---|---|
| `cl.C`, `st.B`, `far D`, `B` | botón sin dirección |
| `cr.A` | abajo + botón |
| `f+B`, `df+C`, `uf+D`… | dirección + botón |
| `qcf+A`, `dp+C`, `hcb f+P`, `qcb hcf+K`… | movimiento + botón |
| `[2]8+D`, `[4]6+C` | carga (abajo→arriba, atrás→adelante) |
| `66` | correr |
| `P` = A o C · `K` = B o D · `A/C` = cualquiera · `AC` = a la vez | botones |

Para el modo rekka, agrega `rekkas = { ... }` con el mismo formato al personaje.

## Créditos

- Direcciones de memoria de KOF 2002 (vida, barras, contador de golpes, tiempo): [peon2/fbneo-training-mode](https://github.com/peon2/fbneo-training-mode).
- Listas de movimientos y combos: [Dream Cancel Wiki](https://dreamcancel.com/) (páginas de KOF 2002 y 2002 UM).
- *The King of Fighters 2002* es propiedad de SNK. Este proyecto no incluye ni distribuye ROMs.

## Licencia

[MIT](LICENSE)

---

## English summary

**BETA** — Combo Trials mode for *The King of Fighters 2002* on Fightcade / FBNeo, written in Lua. It covers 43 characters and 174 combos and shows arrow and button icons. It checks your actual inputs (motions, charges, simultaneous buttons) and reads the game's hit counter to detect dropped combos. It also has a rekka mode (Kim), a 10-rep counter, and loads automatically as an addon of fbneo-training-mode. Most combos are **not yet verified in-game for every character**. Reports and fixes are welcome. See the Spanish sections above for install steps, controls (hold Start + direction/button) and the combo notation.
