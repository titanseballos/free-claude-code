# Revisión del Repositorio: techchipnet/hound

**URL:** https://github.com/techchipnet/hound  
**Versión revisada:** v0.2  
**Fecha de revisión:** 2026-04-28

---

## Resumen Ejecutivo

Hound es una herramienta de recopilación de información y captura de coordenadas GPS remotas. Utiliza un servidor PHP local con un túnel Cloudflared para generar un enlace público que, al ser visitado por un objetivo, captura su ubicación geográfica, información del dispositivo y datos de red. El autor la presenta como herramienta de pentesting.

---

## Arquitectura

| Componente | Tecnología | Rol |
|---|---|---|
| `hound.sh` | Bash | Orquestador principal: instala dependencias, levanta servidor PHP y túnel |
| `index.php` | PHP | Punto de entrada: incluye `ip.php` y redirige al chat falso |
| `ip.php` | PHP | Captura IP y User-Agent, los escribe en `ip.txt` |
| `webhook.php` | PHP | Recibe JSON con datos del dispositivo/GPS y los anexa a `data.txt` |
| `script.js` | JavaScript | Interfaz de chat falsa para mantener al objetivo distraído |
| `index_chat.html` | HTML/CSS | Página de señuelo que solicita permisos de geolocalización al navegador |

### Flujo de ataque

```
Atacante ejecuta hound.sh
  → Se levanta servidor PHP en localhost:8080
  → cloudflared genera URL pública (https://xxx.trycloudflare.com)
  → Atacante comparte esa URL con el objetivo
Objetivo abre el enlace
  → ip.php registra IP + User-Agent → ip.txt
  → El navegador solicita permiso de geolocalización (API del navegador)
  → Si el objetivo acepta: script.js envía coords a webhook.php → data.txt
  → Interfaz de chat falsa mantiene al objetivo en la página
Atacante lee ip.txt y data.txt en tiempo real
```

---

## Análisis de Calidad del Código

### Problemas críticos

**1. `webhook.php` — escritura directa sin validación**
```php
$data = json_decode(file_get_contents('php://input'), true);
file_put_contents('data.txt', $data, FILE_APPEND);
```
- `$data` puede ser cualquier tipo (array, string, null). Pasar un array directamente a `file_put_contents` genera una advertencia PHP y escribe `"Array"` literal en el archivo; los datos GPS reales se pierden.
- No hay validación de campos ni sanitización del input.
- Cualquier persona que conozca la URL del webhook puede escribir datos arbitrarios en `data.txt`.

**2. `ip.php` — sin autenticación de origen**
```php
$ip = $_SERVER['HTTP_CLIENT_IP'] ?? $_SERVER['HTTP_X_FORWARDED_FOR'] ?? $_SERVER['REMOTE_ADDR'];
```
- Los headers `HTTP_CLIENT_IP` y `HTTP_X_FORWARDED_FOR` son controlables por el cliente; un objetivo sofisticado puede falsificar su IP.
- No hay ningún mecanismo de autenticación; cualquiera puede disparar el endpoint.

**3. `index.php` — error de sintaxis**
```php
exit   // falta el punto y coma
```
- En PHP 8+ esto lanza un error de análisis que rompe la redirección.

**4. `hound.sh` — descarga de binario sin verificación de integridad**
```bash
wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm -O cloudflared
```
- No se verifica ningún hash (SHA256/SHA512) ni firma GPG del binario descargado.
- Un atacante con capacidad de MITM o que comprometa el servidor de descarga puede sustituir el binario por código malicioso.

### Problemas menores

- `data.txt` e `ip.txt` se acumulan indefinidamente; no hay rotación ni límite de tamaño.
- El script no limpia los archivos de datos entre ejecuciones, mezclando sesiones.
- No hay logging estructurado; la salida de depuración se mezcla con la salida al usuario.
- La interfaz de chat es cosmética y no agrega funcionalidad real al ataque.

---

## Análisis de Seguridad (del código en sí)

| Riesgo | Severidad | Descripción |
|---|---|---|
| Input sin validar en webhook | Alta | Escritura directa de datos externos a archivo del sistema |
| Spoofing de IP | Media | Headers HTTP modificables por el cliente |
| Binario sin firma | Alta | Posibilidad de ejecución de código arbitrario durante instalación |
| Sin autenticación en endpoints | Media | Cualquier actor puede invocar ip.php / webhook.php |
| Error de sintaxis PHP | Baja | `exit` sin punto y coma en index.php |
| Acumulación ilimitada de datos | Baja | Sin rotación de archivos de log |

---

## Consideraciones Éticas y Legales

Hound está diseñado para recopilar información de personas sin su consentimiento explícito informado. Si bien el repositorio incluye un disclaimer de "solo para pentesting", las características del flujo de ataque indican que:

- El objetivo no sabe que está siendo rastreado.
- La interfaz de chat es un señuelo deliberado.
- La solicitud de geolocalización del navegador es la única interacción visible, pero el objetivo no conoce su propósito real.

**Usar esta herramienta contra personas sin autorización escrita previa es ilegal** en la mayoría de jurisdicciones (CFAA en EE.UU., Directiva NIS2 en Europa, Ley Federal de Telecomunicaciones en México, entre otras). Su uso legítimo se restringe a:

- Pruebas de penetración con contrato y alcance definido.
- Entornos de laboratorio controlados (CTFs, red interna propia).
- Investigación defensiva para entender técnicas de phishing de geolocalización.

---

## Conclusiones

Hound implementa una técnica conocida de phishing de geolocalización de forma funcional pero con calidad de código baja. Los problemas más importantes son la escritura directa de input externo sin validación en `webhook.php` y la descarga de binarios sin verificación de integridad en `hound.sh`. Para un entorno de pentesting profesional, la herramienta requeriría:

1. Validación y sanitización del JSON recibido en `webhook.php`.
2. Verificación de hash SHA256 al descargar `cloudflared`.
3. Corrección del error de sintaxis en `index.php`.
4. Mecanismo de autenticación básico para los endpoints PHP.
5. Rotación/limpieza de archivos de datos entre sesiones.

**Archivos revisados:** `hound.sh`, `index.php`, `ip.php`, `webhook.php`, `script.js`, `README.md`  
**Método de verificación:** Análisis estático del código fuente mediante lectura directa de los archivos del repositorio.  
**Riesgos residuales:** La herramienta puede ser usada con fines maliciosos; su descarga e implementación deben hacerse solo en contextos autorizados.
