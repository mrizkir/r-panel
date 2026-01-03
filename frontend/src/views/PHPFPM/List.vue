<template>
  <div>
    <v-row>
      <v-col cols="12">
        <h1 class="text-h4 mb-4">PHP-FPM Pools</h1>
        <v-btn color="primary" @click="showCreateDialog = true">
          <v-icon left>mdi-plus</v-icon>
          Create Pool
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
                  <th>PHP Version</th>
                  <th>Status</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="pool in pools" :key="pool.name">
                  <td>{{ pool.name }}</td>
                  <td>{{ pool.php_version }}</td>
                  <td>
                    <v-chip :color="pool.status === 'active' ? 'success' : 'default'" size="small">
                      {{ pool.status }}
                    </v-chip>
                  </td>
                  <td>
                    <v-btn icon size="small" @click="editPool(pool)">
                      <v-icon>mdi-pencil</v-icon>
                    </v-btn>
                    <v-btn icon size="small" @click="deletePool(pool)">
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

const pools = ref([])
const showCreateDialog = ref(false)

async function loadPools() {
  try {
    const response = await api.get('/phpfpm/pools')
    pools.value = response.data.pools || []
  } catch (error) {
    console.error('Failed to load pools:', error)
  }
}

function editPool(pool) {
  // TODO: Implement edit
  console.log('Edit pool:', pool)
}

async function deletePool(pool) {
  if (!confirm(`Delete pool ${pool.name}?`)) return
  
  try {
    await api.delete(`/phpfpm/pools/${pool.php_version}/${pool.name}`)
    loadPools()
  } catch (error) {
    console.error('Failed to delete pool:', error)
  }
}

onMounted(() => {
  loadPools()
})
</script>

