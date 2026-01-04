<template>
  <div>
    <v-row>
      <v-col cols="12">
        <h1 class="text-h4 mb-4">Dashboard</h1>
      </v-col>
    </v-row>

    <v-row>
      <v-col cols="12" md="4">
        <v-card>
          <v-card-title>CPU Usage</v-card-title>
          <v-card-text>
            <div class="text-h3">{{ stats?.cpu?.usage_percent?.toFixed(1) || 0 }}%</div>
            <div class="text-caption">{{ stats?.cpu?.cores || 0 }} cores</div>
          </v-card-text>
        </v-card>
      </v-col>
      <v-col cols="12" md="4">
        <v-card>
          <v-card-title>Memory Usage</v-card-title>
          <v-card-text>
            <div class="text-h3">{{ stats?.memory?.used_percent?.toFixed(1) || 0 }}%</div>
            <div class="text-caption">
              {{ formatBytes(stats?.memory?.used || 0) }} / {{ formatBytes(stats?.memory?.total || 0) }}
            </div>
          </v-card-text>
        </v-card>
      </v-col>
      <v-col cols="12" md="4">
        <v-card>
          <v-card-title>Uptime</v-card-title>
          <v-card-text>
            <div class="text-h6">{{ stats?.uptime || 'N/A' }}</div>
          </v-card-text>
        </v-card>
      </v-col>
    </v-row>

    <v-row>
      <v-col cols="12">
        <v-card>
          <v-card-title>Services Status</v-card-title>
          <v-card-text>
            <v-list>
              <v-list-item
                v-for="service in services"
                :key="service.name"
                :prepend-icon="service.active ? 'mdi-check-circle' : 'mdi-close-circle'"
                :prepend-icon-color="service.active ? 'success' : 'error'"
              >
                <v-list-item-title>{{ service.name }}</v-list-item-title>
                <v-list-item-subtitle>{{ service.status }}</v-list-item-subtitle>
              </v-list-item>
            </v-list>
          </v-card-text>
        </v-card>
      </v-col>
    </v-row>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import api from '../services/api'

const stats = ref(null)
const services = ref([])

async function loadStats() {
  try {
    const response = await api.get('/monitoring/stats')
    stats.value = response.data
  } catch (error) {
    console.error('Failed to load stats:', error)
  }
}

async function loadServices() {
  try {
    const response = await api.get('/monitoring/services')
    services.value = response.data.services || []
  } catch (error) {
    console.error('Failed to load services:', error)
  }
}

function formatBytes(bytes) {
  if (!bytes) return '0 B'
  const k = 1024
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB']
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return Math.round(bytes / Math.pow(k, i) * 100) / 100 + ' ' + sizes[i]
}

onMounted(() => {
  loadStats()
  loadServices()
  setInterval(() => {
    loadStats()
    loadServices()
  }, 5000) // Refresh every 5 seconds
})
</script>

