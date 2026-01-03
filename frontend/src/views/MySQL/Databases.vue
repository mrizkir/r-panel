<template>
  <div>
    <v-row>
      <v-col cols="12">
        <h1 class="text-h4 mb-4">MySQL Databases</h1>
        <v-btn color="primary" @click="showCreateDialog = true">
          <v-icon left>mdi-plus</v-icon>
          Create Database
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
                  <th>Size</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="db in databases" :key="db.name">
                  <td>{{ db.name }}</td>
                  <td>{{ db.size }}</td>
                  <td>
                    <v-btn icon size="small" @click="deleteDatabase(db)">
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

const databases = ref([])
const showCreateDialog = ref(false)

async function loadDatabases() {
  try {
    const response = await api.get('/mysql/databases')
    databases.value = response.data.databases || []
  } catch (error) {
    console.error('Failed to load databases:', error)
  }
}

async function deleteDatabase(db) {
  if (!confirm(`Delete database ${db.name}?`)) return
  
  try {
    await api.delete(`/mysql/databases/${db.name}`)
    loadDatabases()
  } catch (error) {
    console.error('Failed to delete database:', error)
  }
}

onMounted(() => {
  loadDatabases()
})
</script>

