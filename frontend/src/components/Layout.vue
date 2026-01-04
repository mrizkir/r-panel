<template>
  <v-app>
    <v-app-bar color="primary" dark>
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
          <v-list-item :to="{ name: 'Profile' }">
            <v-list-item-title>Profil</v-list-item-title>
            <template v-slot:prepend>
              <v-icon>mdi-account</v-icon>
            </template>
          </v-list-item>
          <v-divider />
          <v-list-item @click="handleLogout">
            <v-list-item-title>Logout</v-list-item-title>
            <template v-slot:prepend>
              <v-icon>mdi-logout</v-icon>
            </template>
          </v-list-item>
        </v-list>
      </v-menu>
      
      <!-- Horizontal Menu Tabs as App Bar Extension -->
      <template v-slot:extension>
        <v-tabs
          v-model="activeTab"
          mandatory
          color="white"
          bg-color="grey-lighten-4"
          density="compact"
          align-tabs="start"
          class="tabs-menu"
          @update:model-value="handleTabChange"
        >
          <v-tab value="dashboard">Dashboard</v-tab>
          <v-tab value="client">Client</v-tab>
          <v-tab value="sites">Sites</v-tab>
          <v-tab value="email" disabled>Email</v-tab>
          <v-tab value="dns" disabled>DNS</v-tab>
          <v-tab value="monitor">Monitor</v-tab>
          <v-tab value="help" disabled>Help</v-tab>
          <v-tab value="tools" disabled>Tools</v-tab>
          <v-tab value="system">System</v-tab>
        </v-tabs>
      </template>
    </v-app-bar>

    <!-- Sidebar dengan Sub-menu -->
    <v-navigation-drawer permanent width="250">
      <LayoutDashboard v-if="activeTab === 'dashboard'" />
      <LayoutClient v-else-if="activeTab === 'client'" />
      <LayoutSites v-else-if="activeTab === 'sites'" />
      <LayoutMonitor v-else-if="activeTab === 'monitor'" />
      <LayoutSystem v-else-if="activeTab === 'system'" />
      <LayoutDashboard v-else />
    </v-navigation-drawer>

    <v-main>
      <v-container fluid>
        <router-view />
      </v-container>
    </v-main>
  </v-app>
</template>

<script setup>
import { ref, watch, onMounted } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { useAuthStore } from '../stores/auth'
import LayoutDashboard from './LayoutDashboard.vue'
import LayoutClient from './LayoutClient.vue'
import LayoutSites from './LayoutSites.vue'
import LayoutMonitor from './LayoutMonitor.vue'
import LayoutSystem from './LayoutSystem.vue'

const router = useRouter()
const route = useRoute()
const authStore = useAuthStore()
const activeTab = ref('dashboard')

// Determine active tab based on current route
function getActiveTabFromRoute() {
  const routeName = route.name
  if (routeName === 'Dashboard') return 'dashboard'
  if (routeName === 'ClientList' || routeName === 'ClientAdd' || 
      routeName === 'ResellerList' || routeName === 'ResellerAdd' ||
      routeName === 'ClientCircleList' || routeName === 'ClientMessage' ||
      routeName === 'ClientTemplateList' || routeName === 'MessageTemplateList') return 'client'
  if (routeName === 'MySQL' || routeName === 'Backups') return 'sites'
  if (routeName === 'Logs') return 'monitor'
  if (routeName === 'PHPFPM' || routeName === 'Nginx' || routeName === 'Users') return 'system'
  return 'dashboard'
}

// Handle tab change from v-tabs v-model
function handleTabChange(tab) {
  // If tab has direct route, navigate to it
  if (tab === 'dashboard') {
    router.push({ name: 'Dashboard' }).catch(() => {})
  } else if (tab === 'monitor') {
    router.push({ name: 'Logs' }).catch(() => {})
  } else if (tab === 'client') {
    // Don't navigate if already on a client route or if routes don't exist yet
    // Just show the menu, user can click on menu items when routes are ready
    const clientRoutes = ['ClientList', 'ClientAdd', 'ResellerList', 'ResellerAdd', 
                          'ClientCircleList', 'ClientMessage', 
                          'ClientTemplateList', 'MessageTemplateList']
    // Only navigate if we're not already on a client route
    // But don't navigate if route doesn't exist - just show the menu
    if (!clientRoutes.includes(route.name)) {
      // Check if route exists before navigating
      try {
        const resolved = router.resolve({ name: 'ClientList' })
        if (resolved.name === 'ClientList') {
          router.push({ name: 'ClientList' }).catch(() => {
            // Route doesn't exist, just show menu
          })
        }
      } catch (error) {
        // Route doesn't exist, just keep showing the menu without navigation
      }
    }
  } else if (tab === 'sites') {
    // Redirect to first sub-menu item if not already on a sites route
    if (route.name !== 'MySQL' && route.name !== 'Backups') {
      router.push({ name: 'MySQL' }).catch(() => {})
    }
  } else if (tab === 'system') {
    // Redirect to first sub-menu item if not already on a system route
    if (route.name !== 'PHPFPM' && route.name !== 'Nginx' && route.name !== 'Users') {
      router.push({ name: 'PHPFPM' }).catch(() => {})
    }
  }
  // Sites and System tabs show sub-menu and navigate to first item if needed
}

// Watch route changes to update active tab
watch(() => route.name, () => {
  activeTab.value = getActiveTabFromRoute()
}, { immediate: true })

// Initialize active tab on mount
onMounted(() => {
  activeTab.value = getActiveTabFromRoute()
})

async function handleLogout() {
  await authStore.logout()
  router.push('/login')
}
</script>

