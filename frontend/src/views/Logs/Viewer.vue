<template>
  <div>
    <v-row>
      <v-col cols="12">
        <h1 class="text-h4 mb-4">System Logs</h1>
      </v-col>
    </v-row>

    <v-row>
      <v-col cols="12">
        <v-tabs v-model="tab">
          <v-tab value="system">System</v-tab>
          <v-tab value="nginx-access">Nginx Access</v-tab>
          <v-tab value="nginx-error">Nginx Error</v-tab>
          <v-tab value="phpfpm">PHP-FPM</v-tab>
        </v-tabs>

        <v-card>
          <v-card-text>
            <div class="log-viewer">
              <div v-for="(log, index) in logs" :key="index" class="log-line">
                {{ log }}
              </div>
            </div>
          </v-card-text>
        </v-card>
      </v-col>
    </v-row>
  </div>
</template>

<script setup>
import { ref, watch, onMounted } from 'vue'
import api from '../../services/api'

const tab = ref('system')
const logs = ref([])

async function loadLogs() {
  try {
    let response
    switch (tab.value) {
      case 'system':
        response = await api.get('/logs/system')
        break
      case 'nginx-access':
        response = await api.get('/logs/nginx/access')
        break
      case 'nginx-error':
        response = await api.get('/logs/nginx/error')
        break
      case 'phpfpm':
        response = await api.get('/logs/phpfpm')
        break
    }
    logs.value = response.data.logs || []
  } catch (error) {
    console.error('Failed to load logs:', error)
    logs.value = []
  }
}

watch(tab, () => {
  loadLogs()
})

onMounted(() => {
  loadLogs()
  setInterval(loadLogs, 5000) // Refresh every 5 seconds
})
</script>

<style scoped>
.log-viewer {
  background: #1e1e1e;
  color: #d4d4d4;
  padding: 16px;
  border-radius: 4px;
  max-height: 600px;
  overflow-y: auto;
  font-family: 'Courier New', monospace;
  font-size: 12px;
}

.log-line {
  margin-bottom: 4px;
  white-space: pre-wrap;
  word-break: break-all;
}
</style>

