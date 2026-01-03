<script setup>
  import { ref } from 'vue'
  
  const drawer = ref(false)
  </script>
  
  <template>
    <v-app>
      <v-app-bar color="primary" dark>
        <v-app-bar-nav-icon @click="drawer = !drawer"></v-app-bar-nav-icon>
        <v-toolbar-title>R-Panel</v-toolbar-title>
      </v-app-bar>
  
      <v-navigation-drawer v-model="drawer" temporary>
        <v-list>
          <v-list-item prepend-icon="mdi-home" title="Home" value="home"></v-list-item>
          <v-list-item prepend-icon="mdi-cog" title="Settings" value="settings"></v-list-item>
        </v-list>
      </v-navigation-drawer>
  
      <v-main>
        <v-container>
          <v-row>
            <v-col cols="12">
              <v-card>
                <v-card-title>Welcome to R-Panel</v-card-title>
                <v-card-text>
                  <p>Vuetify is now installed and working!</p>
                  <v-btn color="primary" class="mt-4">Click Me</v-btn>
                </v-card-text>
              </v-card>
            </v-col>
          </v-row>
        </v-container>
      </v-main>
    </v-app>
  </template>