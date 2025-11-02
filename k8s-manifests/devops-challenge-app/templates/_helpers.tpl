{{/*
Expand the name of the chart.
*/}}
{{- define "devops-challenge-app.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "devops-challenge-app.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "devops-challenge-app.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "devops-challenge-app.labels" -}}
helm.sh/chart: {{ include "devops-challenge-app.chart" . }}
{{ include "devops-challenge-app.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
project: devops-challenge
{{- end }}

{{/*
Selector labels
*/}}
{{- define "devops-challenge-app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "devops-challenge-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
MongoDB labels
*/}}
{{- define "devops-challenge-app.mongodb.labels" -}}
helm.sh/chart: {{ include "devops-challenge-app.chart" . }}
app.kubernetes.io/name: {{ include "devops-challenge-app.name" . }}-mongodb
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
project: devops-challenge
{{- end }}

{{/*
MongoDB selector labels
*/}}
{{- define "devops-challenge-app.mongodb.selectorLabels" -}}
app.kubernetes.io/name: {{ include "devops-challenge-app.name" . }}-mongodb
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "devops-challenge-app.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "devops-challenge-app.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
MongoDB Secret Name
*/}}
{{- define "devops-challenge-app.mongodb.secretName" -}}
{{- if .Values.mongodbSecret.existingSecret }}
{{- .Values.mongodbSecret.existingSecret }}
{{- else }}
{{- printf "%s-mongodb-secret" (include "devops-challenge-app.fullname" .) }}
{{- end }}
{{- end }}



