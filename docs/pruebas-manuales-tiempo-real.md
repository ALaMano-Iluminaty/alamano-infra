# Pruebas manuales de tiempo real

Tres pruebas que no se pueden automatizar sin navegador, porque lo que hay que
verificar es exactamente lo que ve el usuario en dos pantallas a la vez.

Todas se corren contra el despliegue real:
**https://alamano.brazilsouth.cloudapp.azure.com**

> El HTTPS no es un lujo: sin él el navegador bloquea la geolocalización y el
> WebSocket seguro, y ninguna de estas tres pruebas se puede hacer.

## Montaje común

Se necesitan **dos sesiones de navegador independientes**, no dos pestañas de la
misma: el token vive en el almacenamiento del navegador y dos pestañas normales
comparten la misma sesión.

| | Ventana | Quién | Pantalla |
|---|---|---|---|
| A | normal | vendedor | `/seller/dashboard` |
| B | incógnito | cliente | `/map` |

En ambas hay que **permitir la ubicación** cuando el navegador la pida. Como las
dos corren en el mismo computador quedan en el mismo punto, que es justo lo que
hace falta para que el vendedor salga como cercano.

Antes de empezar, en cada ventana: *Registrarse* → en A elegir **barbero** y en B
**cliente**. Usar correos distintos y anotarlos; sirven para repetir la prueba.

Deja abiertas las herramientas de desarrollo (F12) en la ventana B, pestaña
**Red**, filtrando por `ws`. Ahí se ve la conexión del tiempo real y es la mitad
de la evidencia.

---

## AB#335 — Dos navegadores ven aparecer y desaparecer un vendedor

**Qué prueba.** Que el mapa del cliente refleja en tiempo real que un vendedor se
conecta y se desconecta, sin recargar la página.

**Pasos**

1. En B, con el mapa abierto, confirma que el vendedor de A **no** aparece.
2. En A, activa el interruptor de disponibilidad. Debe quedar en **En línea**,
   con el texto *"Disponible: los clientes cercanos te ven en el mapa."*
3. **Sin tocar B**, mira el mapa: el marcador del vendedor debe aparecer solo.
4. En A, vuelve a tocar el interruptor hasta que diga **Desconectado**.
5. **Sin tocar B**, el marcador debe desaparecer solo.

**Pasa si** el marcador aparece y desaparece sin que nadie recargue B. Unos
segundos de demora están bien; lo que no vale es tener que refrescar.

**Evidencia.** Un video corto de las dos ventanas lado a lado es lo más claro. Si
no, tres capturas de B: sin el marcador, con el marcador, y sin el marcador otra
vez, con el reloj del sistema visible.

**Si falla.** Mira la pestaña Red de B: la petición a `/ws` debe estar en **101**.
Si está en 502, el Gateway no está arriba. Si quedó en 403 o se cerró sola, lo
primero que hay que revisar es `ALLOWED_ORIGINS` del Gateway, que tiene que traer
el dominio y no `localhost`:
`docker logs alamano-realtime-gateway`.

---

## AB#336 — Cierre brusco de pestaña, caída de red y reconexión

**Qué prueba.** Dos cosas distintas que suelen confundirse: que el vendedor
desaparece del mapa aunque **no** se desconecte por las buenas, y que el cliente
se vuelve a conectar solo cuando se le cae la red.

La parte del servidor ya está cubierta por pruebas automáticas del Gateway
(`disconnectingProfessionalPublishesConnectionLost` y
`disconnectingClientDoesNotPublishConnectionLost`). Lo que no tiene prueba
automática es el reintento del navegador, porque el frontend no tiene corredor de
pruebas. Eso es lo que se verifica a mano aquí.

### Parte 1: cierre brusco

1. En A, ponte **En línea**. Confirma en B que aparece el marcador.
2. Cierra la pestaña A **de golpe** con `Ctrl+W`. Nada de desconectarse primero:
   la gracia es que el servidor se entere solo, por el socket que se cae.
3. En B, el marcador debe desaparecer sin recargar.

**Pasa si** el marcador se va solo. Es el mismo resultado que la prueba anterior,
pero por un camino distinto: aquí nadie avisó.

### Parte 2: caída de red y reconexión

4. Con B abierto en el mapa, en las herramientas de desarrollo ve a **Red** y pon
   la conexión en **Sin conexión** (*Offline*).
5. Espera unos 15 segundos. La app no debe quedar congelada ni botar al login.
6. Vuelve a **Sin limitación** (*No throttling*).
7. Mira la pestaña Red: debe aparecer una **nueva** petición a `/ws` en **101**.
8. Para confirmar que la reconexión sirvió y no solo se ve bonita: con B ya
   reconectado, vuelve a conectar al vendedor en A y comprueba que el marcador
   aparece otra vez en B.

**Pasa si** se reconecta sola y vuelve a recibir eventos. El paso 8 es el que
importa: un socket reconectado que no recibe nada no sirve de nada.

**Evidencia.** Captura de la pestaña Red donde se vean las dos peticiones a `/ws`
(la que se cayó y la nueva en 101), más una captura del marcador reapareciendo.

**Nota sobre los tiempos.** El cliente reintenta con espera creciente: 1s, 2s, 4s
y así hasta un tope de 30s. Si la red estuvo caída un rato largo, la reconexión
puede tardar hasta esos 30 segundos. No es una falla, es el backoff; está en
`socket.ts`.

---

## AB#338 — Sincronización entre vendedor y cliente

**Qué prueba.** Que el cambio de estado que hace el vendedor le llega al cliente
al instante, sin recargar.

Esta sí tiene prueba automática de verdad:
`ServiceChannelIntegrationTest.statusChangeIsDeliveredOnlyToSubscribersOfItsService`
levanta STOMP real con dos suscriptores y verifica que el evento llega al del
servicio y **no** al otro. La prueba manual es para dejar evidencia visual sobre
el despliegue, no para reemplazarla.

**Pasos**

1. En A, ponte **En línea**.
2. En B, toca el marcador del vendedor y dale a **Reservar barbero**. B queda en
   la pantalla de seguimiento.
3. En A debe aparecer el servicio. El estado inicial que ve el cliente es
   **Preparándose**.
4. En A toca **Iniciar trayecto**. En B, sin recargar, el estado debe pasar a
   **En camino**.
5. En A toca **Llegué a la ubicación**. En B debe pasar a **En la puerta**.
6. En A toca **Finalizar servicio**. En B debe pasar a **Servicio finalizado**.

**Pasa si** los cuatro estados se reflejan en B sin recargar y en el mismo orden.

**Evidencia.** Video de las dos ventanas, o cuatro capturas de B con cada estado.

**De paso queda probado AB#340.** Mientras el servicio está activo, en B se ve la
ubicación del vendedor moverse. Apenas finalizas el servicio en el paso 6, esa
ubicación deja de actualizarse: el vendedor ya no tiene un servicio en curso y
tanto el Gateway como el Core descartan lo que mande. En A el texto cambia de
*"Compartiendo tu ubicación"* a *"Tu ubicación deja de compartirse."*

---

## Qué anotar en cada tarea

Para cada una, en Azure DevOps: fecha y hora de la corrida, el commit desplegado
(`git -C ~/alamano/alamano-infra log --oneline -1` en la VM), si pasó o no, y las
capturas o el video. Si algo falló, el error exacto y en qué paso, que es lo que
sirve para arreglarlo.
