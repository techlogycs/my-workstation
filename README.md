# Dotfiles híbridos para Pop!_OS y Ubuntu

Este repositorio aprovisiona una estación de trabajo Pop!_OS o Ubuntu con una estrategia en dos capas:

- Ansible gestiona la capa base del sistema operativo: repositorios APT, paquetes del sistema, Docker, Flatpak guiado por facts, integración con el gestor de archivos y bootstrap de Nix.
- Nix con Home Manager gestiona el entorno de usuario de forma reproducible: Zsh, utilidades de desarrollo y variables de entorno declarativas.
- El DevContainer permite validar, lintar y evolucionar la configuración sin contaminar el host.

## Estructura

```text
dotfiles/
├── .devcontainer/
│   ├── devcontainer.json
│   └── Dockerfile
├── .ansible-lint
├── ansible.cfg
├── ansible/
│   ├── group_vars/
│   │   └── all/
│   │       └── main.yml
│   ├── inventories/
│   │   └── local/
│   │       └── hosts.yml
│   ├── local.yml
│   └── roles/
│       ├── common/
│       ├── system/
│       ├── apt_repositories/
│       ├── desktop_apps/
│       ├── flatpak/
│       ├── docker/
│       ├── file_manager/
│       └── nix/
├── nix/
│   ├── home.nix
│   └── flake.nix
├── bootstrap.sh
└── README.md
```

## Flujo recomendado

1. En el host Pop!_OS o Ubuntu real, ejecuta `./bootstrap.sh`.
2. El script instala `git`, `curl` y `ansible`, clona el repositorio en `~/my-workstation` si hace falta y lanza el playbook local.
3. El playbook configura APT y, según los flags de `ansible/group_vars/all/main.yml`, instala VS Code, Brave, Docker, Flatpak en Ubuntu y Pop!_OS, integración con el gestor de archivos y Nix.
4. Finalmente, Ansible construye y activa Home Manager desde el flake fijado en `nix/`.

## Roles y tags

El playbook usa roles pequeños y etiquetados para que puedas ejecutar solo una parte del aprovisionamiento:

- `common`: validación del host y facts compartidos.
- `system`: paquetes base, herramientas de escritorio y shell por defecto.
- `apt_repositories`: repositorios y llaves APT de proveedores.
- `desktop_apps`: instalación de VS Code y Brave.
- `flatpak`: Flathub y aplicaciones Flatpak por distro.
- `docker`: configuración de `daemon.json` y servicio.
- `file_manager`: integración “Open in Code”.
- `nix`: instalación de Nix y activación de Home Manager.

Ejemplos:

```bash
ansible-playbook ansible/local.yml --tags docker
ansible-playbook ansible/local.yml --tags nix,file-manager
./bootstrap.sh --tags system
```

## DevContainer

El contenedor existe únicamente para desarrollo y validación de la configuración. Incluye:

- `ansible-lint` y `yamllint` para Ansible/YAML.
- `nix`, `home-manager`, `statix` y `nixpkgs-fmt` para evaluar, lintar y formatear la configuración Nix.
- Extensiones de VS Code orientadas a Ansible, Nix y TOML.

La imagen del DevContainer instala directamente `ansible-core`, `ansible-lint`, `yamllint` y Nix. Después, `postCreateCommand` solo añade `home-manager`, `statix` y `nixpkgs-fmt` al perfil del usuario y ejecuta `nix flake check --impure` sobre `nix/`.

Si ya tenías el DevContainer creado antes de estos cambios, reconstruye el contenedor para que las herramientas nuevas queden disponibles en `PATH`.

## Validación manual

Dentro del DevContainer o en una máquina con las dependencias instaladas:

```bash
make lint
make format

ansible-playbook --syntax-check ansible/local.yml
ansible-lint ansible
yamllint .
DOTFILES_USER="$USER" DOTFILES_HOME="$HOME" NIX_SYSTEM="$(nix eval --impure --raw --expr builtins.currentSystem)" nix --extra-experimental-features "nix-command flakes" flake check --impure ./nix
```

El `Makefile` expone también objetivos separados:

- `make lint-ansible`
- `make lint-nix`
- `make format-ansible`
- `make format-nix`

## Configuración

Los componentes opcionales están controlados desde `ansible/group_vars/all/main.yml`:

- Todos los `feature_flags.*` aceptan `enabled`, `disabled` o `auto`. Los booleanos antiguos siguen funcionando porque se normalizan internamente a esos modos.
- `feature_flags.vscode`, `feature_flags.brave`, `feature_flags.docker` y `feature_flags.nix` usan `enabled` por defecto. Hoy en día `auto` se resuelve igual que `enabled` para esos componentes, porque no hay una detección de alternativa equivalente.
- `feature_flags.desktop_tools` usa `auto` por defecto y solo instala tooling específico de escritorio cuando detecta una base compatible.
- `feature_flags.copyq` usa `auto` por defecto y solo instala CopyQ si no detecta otro gestor de portapapeles ya instalado.
- `feature_flags.office_suite` usa `auto` por defecto y solo instala LibreOffice si no detecta otra suite ofimática ya instalada.
- `feature_flags.file_manager_integration` usa `auto` por defecto y solo habilita la integración si VS Code también está habilitado.
- `distro_flatpak_apps` define las aplicaciones de escritorio vía Flatpak por distro.
- `supported_distributions`, `deb_arch_map` y `nix_system_map` convierten facts de Ansible en valores utilizables para APT y Nix en Ubuntu y Pop!_OS, incluyendo hosts ARM64.
- `clipboard_manager_package_candidates` define qué paquetes cuentan como gestor de portapapeles existente a efectos del modo `auto` de CopyQ.
- `office_suite_package_candidates` define qué paquetes cuentan como suite ofimática existente a efectos del modo `auto` de LibreOffice.
- `gnome_desktop_package_candidates` define qué paquetes se consideran evidencia de una sesión GNOME; `gnome-tweaks` solo se añade cuando esa base existe.
- `vscode_file_manager_integration` acepta `auto`, `nautilus`, `desktop-entry` o `disabled`.

El modo `auto` se comporta así:

- Si `nautilus` aparece en los facts de paquetes, crea el script en `~/.local/share/nautilus/scripts/Open in Code`.
- Si `nautilus` no está instalado, crea `~/.local/share/applications/code-open-here.desktop` como alternativa genérica basada en desktop entry. Esto evita asumir GNOME en Pop!_OS, pero no garantiza un menú contextual nativo en gestores como COSMIC Files.

El modo `auto` de CopyQ se comporta así:

- Si ya está instalado `copyq` o algún gestor de portapapeles conocido como `gpaste`, `klipper`, `diodon` o `xfce4-clipman`, no instala nada adicional.
- Si no detecta ninguno, añade `copyq` al conjunto de paquetes base.

El modo `auto` de LibreOffice se comporta así:

- Si ya está instalada una suite conocida como `libreoffice`, `onlyoffice-desktopeditors`, `calligra`, `abiword` o `gnumeric`, no instala nada adicional.
- Si no detecta ninguna, añade `libreoffice` al conjunto de paquetes base.

Las herramientas de escritorio GNOME se comportan así:

- `gnome-tweaks` solo se instala cuando el host ya tiene una pila GNOME detectada.
- Esto evita meter tooling específico de GNOME en equipos Pop!_OS que no estén usando GNOME/Nautilus como entorno principal.

## Decisiones técnicas

- Ubuntu y Pop!_OS usan Flatpak para las aplicaciones de escritorio de terceros; la selección se resuelve a partir de facts de Ansible y se puede diferenciar por distro sin tocar los roles.
- La instalación de Flatpak comprueba primero qué remotos y aplicaciones existen antes de añadir o instalar nada, para mantener la ejecución repetible.
- Docker usa `json-file` con rotación, modo `non-blocking` y buffer acotado para evitar crecimiento descontrolado de logs y reducir bloqueos por I/O, preservando otras claves ya presentes en `daemon.json` como `data-root`.
- Nix se instala con Determinate Systems porque simplifica una instalación consistente en Ubuntu/Pop!_OS.
- Home Manager se activa construyendo el paquete de activación desde el flake del sistema detectado, lo que evita depender de una arquitectura fija o de una instalación previa del ejecutable `home-manager` en el host.
- Home Manager también instala un timer de usuario que limpia periódicamente ficheros antiguos en `~/Downloads` y `~/.cache`, para limitar acumulación de descargas y cachés efímeras sin tocar archivos recientes.
- Home Manager también instala wrappers `npm` y `npx` en `~/.local/bin` para que Bun pueda actuar como sustituto por defecto de `npm` y `npx` en la shell del usuario.
- GitHub Copilot CLI se instala mediante el paquete oficial `@github/copilot` usando el `npm` real de Node.js durante la activación de Home Manager, evitando depender del derivation unfree de Nix.

## Ajustes que probablemente querrás personalizar

- `DOTFILES_REPO_URL` en `bootstrap.sh` si el primer despliegue no parte de un clon Git local.
- El tema de Oh My Zsh en `nix/home.nix`.
- Los wrappers `npm` y `npx` en `nix/home.nix` si prefieres mantener los binarios de Node.js sin Bun como compat layer.
- La política `cleanupPolicy` en `nix/home.nix` si quieres cambiar la frecuencia o la antigüedad máxima de `Downloads` y `~/.cache`.
- `DOTFILES_EDITOR` si desactivas VS Code y quieres que `EDITOR` y `VISUAL` apunten a otro binario.
- Los `feature_flags`, `distro_flatpak_apps` y el modo de integración del gestor de archivos en `ansible/group_vars/all/main.yml`.