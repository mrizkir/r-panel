<template>
  <div>
    <v-row>
      <v-col cols="12">
        <h1 class="text-h4 mb-4">Backups</h1>
        <v-btn color="primary" @click="showCreateDialog = true">
          <v-icon left>mdi-backup-restore</v-icon>
          Create Backup
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
                  <th>Name</th>
                  <th>Type</th>
                  <th>Size</th>
                  <th>Created</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="backup in backups" :key="backup.name">
                  <td>{{ backup.name }}</td>
                  <td>{{ backup.type }}</td>
                  <td>{{ formatBytes(backup.size) }}</td>
                  <td>{{ new Date(backup.created_at).toLocaleString() }}</td>
                  <td>
                    <v-btn icon size="small" @click="restoreBackup(backup)">
                      <v-icon>mdi-restore</v-icon>
                    </v-btn>
                    <v-btn icon size="small" @click="deleteBackup(backup)">
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

const backups = ref([])
const showCreateDialog = ref(false)

async function loadBackups() {
  try {
    const response = await api.get('/backups')
    backups.value = response.data.backups || []
  } catch (error) {
    console.error('Failed to load backups:', error)
  }
}

function formatBytes(bytes) {
  if (!bytes) return '0 B'
  const k = 1024
  const sizes = ['B', 'KB', 'MB', 'GB']
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return Math.round(bytes / Math.pow(k, i) * 100) / 100 + ' ' + sizes[i]
}

function restoreBackup(backup) {
  // TODO: Implement restore
  console.log('Restore backup:', backup)
}

async function deleteBackup(backup) {
  if (!confirm(`Delete backup ${backup.name}?`)) return
  
  try {
    await api.delete(`/backups/${backup.name}`)
    loadBackups()
  } catch (error) {
    console.error('Failed to delete backup:', error)
  }
}

onMounted(() => {
  loadBackups()
})
</script>

