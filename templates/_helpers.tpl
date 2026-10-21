{{/* Labels on every object */}}
{{- define "redb.labels" -}}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
metadata block. Args: dict "root" $ "name" <name> "item" <values entry> "wave" <ArgoCD sync wave>.
Sync waves order the first ArgoCD sync: secrets and ACLs, then databases, then users and roles,
then bindings and ingresses. Helm ignores the annotation.
*/}}
{{- define "redb.metadata" -}}
name: {{ .name }}
labels:
  {{- include "redb.labels" .root | nindent 2 }}
  {{- with .item.labels }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
annotations:
  argocd.argoproj.io/sync-wave: {{ .wave | quote }}
  {{- with .item.annotations }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
{{- end }}

{{/* Role ACL reference. Args: dict "acl" <acl value> "ctx" <path for error messages>. */}}
{{- define "redb.aclRef" -}}
{{- $acl := .acl | default dict -}}
{{- if and $acl.predefined $acl.custom -}}
{{- fail (printf "%s.acl: set either predefined or custom, not both" .ctx) -}}
{{- else if $acl.predefined -}}
kind: redis_acl
name: {{ $acl.predefined | quote }}
{{- else if $acl.custom -}}
kind: RedisEnterpriseACL
name: {{ $acl.custom | quote }}
{{- else -}}
{{- fail (printf "%s.acl: set predefined (an ACL built into the cluster, e.g. \"Full Access\") or custom (a RedisEnterpriseACL name)" .ctx) -}}
{{- end -}}
{{- end }}

{{/* Binding spec. Args: dict "item" <values entry> "kind" <role kind> "ctx" <path for error messages>. */}}
{{- define "redb.bindingSpec" -}}
{{- if not .item.role }}{{ fail (printf "%s.role is required" .ctx) }}{{ end -}}
roleRef:
  kind: {{ .kind }}
  name: {{ .item.role | quote }}
{{- with .item.users }}
subjects:
  {{- range . }}
  - kind: RedisEnterpriseUser
    name: {{ . | quote }}
  {{- end }}
{{- end }}
{{- end }}

{{/* ExternalSecret spec with chart defaults. Args: dict "root" $ "spec" <spec>. */}}
{{- define "redb.externalSecretSpec" -}}
{{- $spec := deepCopy (.spec | default dict) -}}
{{- $defaults := .root.Values.externalSecretDefaults | default dict -}}
{{- if and (not (hasKey $spec "refreshInterval")) $defaults.refreshInterval }}{{ $_ := set $spec "refreshInterval" $defaults.refreshInterval }}{{ end -}}
{{- if and (not (hasKey $spec "secretStoreRef")) $defaults.secretStoreRef }}{{ $_ := set $spec "secretStoreRef" $defaults.secretStoreRef }}{{ end -}}
{{- toYaml $spec }}
{{- end }}
