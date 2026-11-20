# 🛡️ Pipeline de Seguridad para Infraestructura como Código (IaC)

Este repositorio contiene la implementación de un control automático de seguridad para Infraestructura como Código (Terraform, Ansible y Docker). El objetivo principal es bloquear Pull Requests (PR) que introduzcan configuraciones inseguras, garantizando que la infraestructura cumpla con las políticas de seguridad de la organización antes de ser fusionada.

## 🚀 Características Principales

* **Escaneo Automático:** Se ejecuta en cada `push` a `main` y en cada `pull_request`.
* **Herramientas Integradas:** Utiliza **Checkov** (para Terraform, Ansible, Dockerfile y escaneo de secretos) y **ansible-lint** (perfil production).
* **Bloqueo de Merge (Gate):** El pipeline falla si se detectan vulnerabilidades, actuando como un *status check* obligatorio en la protección de la rama `main`.
* **Reportes SARIF:** Los hallazgos se publican automáticamente en la pestaña **Security -> Code Scanning** de GitHub.
* **Políticas Personalizadas:** Incluye una regla propia (`CKV2_CURSO_1`) que exige retención de respaldos mínima en RDS.
* **Excepción Documentada:** Uso controlado y justificado de `checkov:skip` para un riesgo aceptado por el negocio.

## 📂 Estructura del Repositorio

```text
├── .github/workflows/
│   └── iac-security.yml      # Configuración del pipeline de GitHub Actions
├── infra/
│   └── main.tf               # Infraestructura en Terraform (RDS, EC2, S3, etc.)
├── ansible/                  # Playbooks y configuraciones (site.yml)
├── docker/                   # Dockerfile de la aplicación
├── politicas/                # Políticas personalizadas de Checkov (YAML)
├── excepcion/                # Código con la excepción justificada (RIESGO-042)
├── docs/                     # Documentación y entregables
│   └── informe.pdf           # Informe final detallado (Word/PDF)
└── README.md                 # Este archivo
```

## 🛠️ Ejecución Local

Si deseas replicar el análisis de seguridad en tu entorno local, necesitas tener instalado Python y ejecutar:

``` bash
# 1. Instalar herramientas
pip install checkov==3.4.5 ansible-core==2.19.6 ansible-lint==25.6.1

# 2. Escanear Terraform y políticas propias
checkov -d infra --external-checks-dir politicas --compact

# 3. Escanear Ansible
ansible-lint --profile production ansible/
```

## 📄 Informe de la Tarea
El análisis detallado de la línea base, la evidencia de los Pull Requests (bloqueo y remediación), la tabla antes/después de las correcciones, y las conclusiones del proyecto se encuentran documentados en el informe oficial:

Ver el informe completo: [Ver Informe PDF](docs/informe.md)