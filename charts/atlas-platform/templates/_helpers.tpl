{{/*
=============================================================================
Named templates — DRY principle in Helm.
Every template file uses these instead of repeating the same labels/names.
=============================================================================
*/}}

{{/*
Chart full name — used as the base for all resource names.
Truncated to 63 chars (K8s name limit).
*/}}
{{- define "atlas-platform.fullname" -}}
{{- printf "%s" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Chart name.
*/}}
{{- define "atlas-platform.name" -}}
{{- .Chart.Name }}
{{- end }}

{{/*
Common labels — applied to EVERY resource.
These labels enable: kubectl get all -l app.kubernetes.io/name=atlas-platform
*/}}
{{- define "atlas-platform.labels" -}}
app.kubernetes.io/name: {{ include "atlas-platform.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end }}

{{/*
Selector labels — used by Deployment.spec.selector and Service.spec.selector.
Must be a SUBSET of the common labels. Must NOT change after first deploy
(K8s uses these to match pods to deployments).
*/}}
{{- define "atlas-platform.selectorLabels" -}}
app.kubernetes.io/name: {{ include "atlas-platform.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}