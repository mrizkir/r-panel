<template>
  <v-app>
    <v-app-bar color="primary" dark>
      <v-app-bar-nav-icon @click="drawer = !drawer" />
      <v-toolbar-title>R-Panel</v-toolbar-title>
      <v-spacer />
      <v-menu>
        <template v-slot:activator="{ props }">
          <v-btn icon v-bind="props">
            <v-icon>mdi-account-circle</v-icon>
          </v-btn>
        </template>
        <v-list>
          <v-list-item>
            <v-list-item-title>{{ authStore.user?.username }}</v-list-item-title>
            <v-list-item-subtitle>{{ authStore.user?.role }}</v-list-item-subtitle>
          </v-list-item>
          <v-divider />
          <v-list-item @click="handleLogout">
            <v-list-item-title>Logout</v-list-item-title>
          </v-list-item>
        </v-list>
      </v-menu>
    </v-app-bar>

    <v-navigation-drawer v-model="drawer" temporary>
      <v-list>
        <v-list-item
          prepend-icon="mdi-view-dashboard"
          title="Dashboard"
          :to="{ name: 'Dashboard' }"
        />
        <v-list-item
          prepend-icon="mdi-code-tags"
          title="PHP-FPM"
          :to="{ name: 'PHPFPM' }"
        />
        <v-list-item
          prepend-icon="mdi-server-network"
          title="Nginx"
          :to="{ name: 'Nginx' }"
        />
        <v-list-item
          prepend-icon="mdi-database"
          title="MySQL"
          :to="{ name: 'MySQL' }"
        />
        <v-list-item
          prepend-icon="mdi-backup-restore"
          title="Backups"
          :to="{ name: 'Backups' }"
        />
        <v-list-item
          prepend-icon="mdi-account-group"
          title="Users"
          :to="{ name: 'Users' }"
        />
        <v-list-item
          prepend-icon="mdi-text-box-outline"
          title="Logs"
          :to="{ name: 'Logs' }"
        />
      </v-list>
    </v-navigation-drawer>

    <v-main>
      <v-container fluid>
        <router-view />
      </v-container>
    </v-main>
  </v-app>
</template>

<script setup>
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '../stores/auth'

const router = useRouter()
const authStore = useAuthStore()
const drawer = ref(false)

async function handleLogout() {
  await authStore.logout()
  router.push('/login')
}
</script>

