{{- define "owlpane-demo.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "owlpane-demo.namespace" -}}
{{- .Values.namespace }}
{{- end }}

{{- define "owlpane-demo.releaseName" -}}
{{- default .Release.Name .Values.release.name }}
{{- end }}

{{- define "owlpane-demo.labels" -}}
app.kubernetes.io/name: {{ include "owlpane-demo.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
{{- end }}

{{- define "owlpane-demo.helmAnnotations" -}}
meta.helm.sh/release-name: {{ include "owlpane-demo.releaseName" . }}
meta.helm.sh/release-namespace: {{ .Release.Namespace }}
{{- end }}

{{- define "owlpane-demo.selectorLabels" -}}
app.kubernetes.io/name: {{ include "owlpane-demo.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
