<template>
  <v-list nav density="compact">
    <!-- Clients Group -->
    <v-list-group value="clients">
      <template v-slot:activator="{ props }">
        <v-list-item v-bind="props" title="Clients" />
      </template>
      <v-list-item
        title="Edit Client"
        @click="navigateToRoute('ClientList')"
        :active="isActiveRoute('ClientList')"
      />
      <v-list-item
        title="Add Client"
        @click="navigateToRoute('ClientAdd')"
        :active="isActiveRoute('ClientAdd')"
      />
    </v-list-group>

    <!-- Resellers Group -->
    <v-list-group value="resellers">
      <template v-slot:activator="{ props }">
        <v-list-item v-bind="props" title="Resellers" />
      </template>
      <v-list-item
        title="Edit Reseller"
        @click="navigateToRoute('ResellerList')"
        :active="isActiveRoute('ResellerList')"
      />
      <v-list-item
        title="Add Reseller"
        @click="navigateToRoute('ResellerAdd')"
        :active="isActiveRoute('ResellerAdd')"
      />
    </v-list-group>

    <!-- Messaging Group -->
    <v-list-group value="messaging">
      <template v-slot:activator="{ props }">
        <v-list-item v-bind="props" title="Messaging" />
      </template>
      <v-list-item
        title="Edit Client Circle"
        @click="navigateToRoute('ClientCircleList')"
        :active="isActiveRoute('ClientCircleList')"
      />
      <v-list-item
        title="Send Email"
        @click="navigateToRoute('ClientMessage')"
        :active="isActiveRoute('ClientMessage')"
      />
    </v-list-group>

    <!-- Templates Group -->
    <v-list-group value="templates">
      <template v-slot:activator="{ props }">
        <v-list-item v-bind="props" title="Templates" />
      </template>
      <v-list-item
        title="Limit-Templates"
        @click="navigateToRoute('ClientTemplateList')"
        :active="isActiveRoute('ClientTemplateList')"
      />
      <v-list-item
        title="Email-Templates"
        @click="navigateToRoute('MessageTemplateList')"
        :active="isActiveRoute('MessageTemplateList')"
      />
    </v-list-group>
  </v-list>
</template>

<script setup>
import { useRoute, useRouter } from 'vue-router'

const route = useRoute()
const router = useRouter()

function isActiveRoute(routeName) {
  return route.name === routeName
}

function navigateToRoute(routeName) {
  // Try to navigate, catch error if route doesn't exist
  router.push({ name: routeName }).catch((error) => {
    // Route doesn't exist yet, this is expected for routes that haven't been created
    // Do nothing, just prevent error from propagating
  })
}
</script>

