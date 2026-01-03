<template>
  <div>
    <v-row>
      <v-col cols="12">
        <h1 class="text-h4 mb-4">Users</h1>
        <v-btn color="primary" @click="showCreateDialog = true" v-if="authStore.user?.role === 'admin'">
          <v-icon left>mdi-plus</v-icon>
          Create User
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
                  <th>Username</th>
                  <th>Role</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="user in users" :key="user.id">
                  <td>{{ user.username }}</td>
                  <td>{{ user.role }}</td>
                  <td>
                    <v-btn icon size="small" @click="editUser(user)" v-if="authStore.user?.role === 'admin'">
                      <v-icon>mdi-pencil</v-icon>
                    </v-btn>
                    <v-btn icon size="small" @click="deleteUser(user)" v-if="authStore.user?.role === 'admin'">
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
import { useAuthStore } from '../../stores/auth'

const authStore = useAuthStore()
const users = ref([])
const showCreateDialog = ref(false)

async function loadUsers() {
  try {
    const response = await api.get('/users')
    users.value = response.data.users || []
  } catch (error) {
    console.error('Failed to load users:', error)
  }
}

function editUser(user) {
  // TODO: Implement edit
  console.log('Edit user:', user)
}

async function deleteUser(user) {
  if (!confirm(`Delete user ${user.username}?`)) return
  
  try {
    await api.delete(`/users/${user.id}`)
    loadUsers()
  } catch (error) {
    console.error('Failed to delete user:', error)
  }
}

onMounted(() => {
  loadUsers()
})
</script>

