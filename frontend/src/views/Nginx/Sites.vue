<template>
  <div>
    <v-row>
      <v-col cols="12">
        <h1 class="text-h4 mb-4">Nginx Sites</h1>
        <v-btn color="primary" @click="showCreateDialog = true">
          <v-icon left>mdi-plus</v-icon>
          Create Site
        </v-btn>
      </v-col>
    </v-row>

    <v-row>
      <v-col cols="12">
        <v-card>
          <v-card-text>
            <v-table>
              <thead>
                <tr>
                  <th>Domain</th>
                  <th>Status</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="site in sites" :key="site.domain">
                  <td>{{ site.domain }}</td>
                  <td>
                    <v-chip :color="site.enabled ? 'success' : 'default'" size="small">
                      {{ site.enabled ? 'Enabled' : 'Disabled' }}
                    </v-chip>
                  </td>
                  <td>
                    <v-btn icon size="small" @click="toggleSite(site)">
                      <v-icon>{{ site.enabled ? 'mdi-toggle-switch' : 'mdi-toggle-switch-off' }}</v-icon>
                    </v-btn>
                    <v-btn icon size="small" @click="editSite(site)">
                      <v-icon>mdi-pencil</v-icon>
                    </v-btn>
                    <v-btn icon size="small" @click="deleteSite(site)">
                      <v-icon>mdi-delete</v-icon>
                    </v-btn>
                  </td>
                </tr>
              </tbody>
            </v-table>
          </v-card-text>
        </v-card>
      </v-col>
    </v-row>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import api from '../../services/api'

const sites = ref([])
const showCreateDialog = ref(false)

async function loadSites() {
  try {
    const response = await api.get('/nginx/sites')
    sites.value = response.data.sites || []
  } catch (error) {
    console.error('Failed to load sites:', error)
  }
}

async function toggleSite(site) {
  try {
    if (site.enabled) {
      await api.post(`/nginx/sites/${site.domain}/disable`)
    } else {
      await api.post(`/nginx/sites/${site.domain}/enable`)
    }
    loadSites()
  } catch (error) {
    console.error('Failed to toggle site:', error)
  }
}

function editSite(site) {
  // TODO: Implement edit
  console.log('Edit site:', site)
}

async function deleteSite(site) {
  if (!confirm(`Delete site ${site.domain}?`)) return
  
  try {
    await api.delete(`/nginx/sites/${site.domain}`)
    loadSites()
  } catch (error) {
    console.error('Failed to delete site:', error)
  }
}

onMounted(() => {
  loadSites()
})
</script>

