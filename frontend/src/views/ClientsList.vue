<template>
  <div>
    <v-row>
      <v-col cols="12">
        <h1 class="text-h4 mb-4">Client List</h1>
      </v-col>
    </v-row>

    <v-row>
      <v-col cols="12">
        <v-data-table
          :headers="headers"
          :items="clients"
          :loading="loading"
          :items-per-page="itemsPerPage"
          :items-per-page-options="[5, 15, 25, 50, 100]"
          :server-items-length="totalItems"
          :page="page"
          @update:page="handlePageChange"
          @update:items-per-page="handleItemsPerPageChange"
          class="elevation-1"
        >
              <template v-slot:item.id="{ item }">
                <a href="#" @click.prevent="editClient(item)">{{ item.id }}</a>
              </template>

              <template v-slot:item.locked="{ item }">
                <a href="#" @click.prevent="editClient(item)">
                  {{ item.locked ? 'Yes' : 'No' }}
                </a>
              </template>

              <template v-slot:item.company_name="{ item }">
                <a href="#" @click.prevent="editClient(item)">
                  {{ item.company_name || '-' }}
                </a>
              </template>

              <template v-slot:item.contact_name="{ item }">
                <a href="#" @click.prevent="editClient(item)">
                  {{ item.contact_name || '-' }}
                </a>
              </template>

              <template v-slot:item.customer_no="{ item }">
                <a href="#" @click.prevent="editClient(item)">
                  {{ item.customer_no || '-' }}
                </a>
              </template>

              <template v-slot:item.username="{ item }">
                <a href="#" @click.prevent="editClient(item)" :title="item.user?.username">
                  {{ item.user?.username || '-' }}
                </a>
              </template>

              <template v-slot:item.city="{ item }">
                <a href="#" @click.prevent="editClient(item)">
                  {{ item.city || '-' }}
                </a>
              </template>

              <template v-slot:item.country="{ item }">
                <a href="#" @click.prevent="editClient(item)">
                  <span v-if="item.country" class="flags" :class="`flag-${item.country.toLowerCase()}`">
                    {{ getCountryName(item.country) }}
                  </span>
                  <span v-else>-</span>
                </a>
              </template>

              <template v-slot:item.actions="{ item }">
                <div class="text-right">
                  <v-btn
                    icon
                    size="small"
                    color="success"
                    @click="loginAsClient(item)"
                    class="mr-1"
                    title="Login as Client"
                  >
                    <v-icon>mdi-login</v-icon>
                  </v-btn>
                  <v-btn
                    icon
                    size="small"
                    color="error"
                    @click="deleteClient(item)"
                    title="Delete Client"
                    v-if="authStore.user?.role === 'admin'"
                  >
                    <v-icon>mdi-delete</v-icon>
                  </v-btn>
                </div>
              </template>
            </v-data-table>
      </v-col>
    </v-row>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import api from '../services/api'
import { useAuthStore } from '../stores/auth'
import { useRouter } from 'vue-router'

const authStore = useAuthStore()
const router = useRouter()

const clients = ref([])
const loading = ref(false)
const page = ref(1)
const itemsPerPage = ref(15)
const totalItems = ref(0)

const headers = [
  { title: 'ID', key: 'id', align: 'start', width: '80px' },
  { title: 'Locked', key: 'locked', align: 'start', width: '80px' },
  { title: 'Company name', key: 'company_name', align: 'start' },
  { title: 'Contact name', key: 'contact_name', align: 'start' },
  { title: 'Customer No.', key: 'customer_no', align: 'start' },
  { title: 'Username', key: 'username', align: 'start' },
  { title: 'City', key: 'city', align: 'start' },
  { title: 'Country', key: 'country', align: 'start' },
  { title: 'Actions', key: 'actions', align: 'end', sortable: false, width: '120px' },
]

// Country code to name mapping (simplified - you can expand this)
const countryNames = {
  'ID': 'Indonesia',
  'US': 'United States',
  'GB': 'United Kingdom',
  // Add more as needed
}

function getCountryName(code) {
  return countryNames[code] || code
}

async function loadClients() {
  loading.value = true
  try {
    const response = await api.get('/clients', {
      params: {
        page: page.value,
        limit: itemsPerPage.value,
      },
    })
    
    if (response.data && response.data.clients) {
      clients.value = response.data.clients
      totalItems.value = response.data.total || 0
    } else {
      clients.value = []
      totalItems.value = 0
    }
  } catch (error) {
    console.error('Failed to load clients:', error)
    clients.value = []
    totalItems.value = 0
  } finally {
    loading.value = false
  }
}

function handlePageChange(newPage) {
  page.value = newPage
  loadClients()
}

function handleItemsPerPageChange(newItemsPerPage) {
  itemsPerPage.value = newItemsPerPage
  page.value = 1 // Reset to first page when changing items per page
  loadClients()
}

function editClient(client) {
  // TODO: Navigate to edit client page
  console.log('Edit client:', client)
  // router.push({ name: 'ClientEdit', params: { id: client.id } })
}

function loginAsClient(client) {
  // TODO: Implement login as client
  console.log('Login as client:', client)
}

async function deleteClient(client) {
  if (!confirm(`Do you really want to delete client ${client.contact_name || client.id}?`)) {
    return
  }
  
  try {
    await api.delete(`/clients/${client.id}`)
    loadClients()
  } catch (error) {
    console.error('Failed to delete client:', error)
    alert('Failed to delete client')
  }
}

onMounted(() => {
  loadClients()
})
</script>

<style scoped>
.flags {
  display: inline-block;
  padding: 2px 6px;
  border-radius: 3px;
  font-size: 0.85em;
}

/* You can add flag icons CSS here if needed */
</style>

