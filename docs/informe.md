# Tarea: Análisis de seguridad IaC en el pipeline

**Curso:** Ciberseguridad  
**Universidad Galileo, FISICC**  
**Postgrado en Diseño y Desarrollo de Software**

## Integrantes

| Nombre | Carné | Usuario GitHub |
|---|---|---|
| Gabriela Lucía Navarro de León | 20000127 | Gabriela-Navarro |
| Sandra Daniela Soria Palma | 20002619 | sandra381 |

**Repositorio:** https://github.com/sandra381/Iac-security-pipeline


## 1. Línea base

Antes de crear el pipeline, se realizó un análisis local sobre la versión insegura del proyecto (commit `31e45b09`, "Versión insegura de práctica"). El análisis se hizo sobre los archivos de demo indicados en la guía de la tarea, copiados en `infra/`, `docker/` y `ansible/`. Estos archivos contienen configuraciones inseguras a propósito para que las herramientas puedan detectarlas.

Para esto se utilizaron Checkov 3.4.5 y ansible-lint 25.6.1.

```bash
checkov -d . --compact
ansible-lint --profile production ansible/
```

### Conteo de fallas por tipo de archivo

| Tipo de archivo | Herramienta | Pasaron | Fallaron |
|---|---|---|---|
| Terraform (`infra/main.tf`) | Checkov | 15 | 24 |
| Dockerfile (`docker/Dockerfile`) | Checkov | 25 | 5 |
| Secretos | Checkov | 0 | 1 |
| Ansible (`ansible/site.yml`) | ansible-lint | No se pudo analizar (error de indentación) | 1 |
| **Total** | | | **31** |

![Resultado de Checkov en la línea base](../imgs/linea_base_checkov.png)

En el caso de Ansible, se encontró el error `load-failure[yaml]`. Esto sucedió porque el archivo `site.yml` tenía problemas de indentación y ansible-lint no podía leerlo correctamente.

Al revisar el archivo manualmente, también se encontraron otras configuraciones inseguras, como conexiones que no verificaban los certificados de seguridad, el uso de `shell` para ejecutar instrucciones en el servidor y archivos con permisos `0777`, que permiten a cualquier usuario del sistema leerlos, modificarlos y ejecutarlos.

![Resultado de ansible-lint en la línea base](../imgs/linea_base_ansible_lint.png)

### Los 5 hallazgos más graves y sus riesgos

Como Checkov en su versión gratuita no muestra la severidad, ordenamos los hallazgos según lo que consideramos más peligroso. Primero colocamos los recursos expuestos directamente a internet, luego las credenciales que podrían quedar expuestas y por último los datos que no cuentan con protección.

1. **CKV_AWS_24 – Acceso SSH abierto:** El servidor permite conexiones SSH desde cualquier dirección IP, por lo que cualquier persona en internet podría intentar acceder sin autorización.

2. **CKV_AWS_17 – Base de datos pública:** La base de datos está configurada para ser accesible desde internet, lo que aumenta el riesgo de ataques y exposición de información.

3. **CKV_SECRET_6 – Contraseña en el código:** Se encontró una contraseña escrita directamente en el código. Esto representa un riesgo porque cualquier persona con acceso al repositorio podría verla y utilizarla.

4. **CKV_AWS_16 – Base de datos sin cifrado:** La base de datos no tiene habilitado el cifrado, por lo que, si alguien obtiene una copia de los datos sin cifrar, podría leer la información.

5. **CKV_AWS_53 al 56 – Bucket S3 sin bloqueo público:** El bucket no tiene configuradas todas las restricciones de acceso público, por lo que los archivos almacenados podrían quedar expuestos a personas no autorizadas.

## 2. Diseño del pipeline

## 3. Evidencia del gate

## 4. Evidencia SARIF

## 5. Remediación

## 6. Excepción documentada

## 7. Política propia

## 8. Conclusiones

## 9. Uso de IA