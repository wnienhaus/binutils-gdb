#include "sysdep.h"
#include "bfd.h"

#ifdef HAVE_WINDOWS_H
#include <windows.h>
#endif /* HAVE_WINDOWS_H  */

#ifdef HAVE_DLFCN_H
#include <dlfcn.h>
#endif /* HAVE_DLFCN_H  */

#define XTENSA_CONFIG_DEFINITION
#include "xtensa-dynconfig.h"

#if !defined (HAVE_DLFCN_H) && defined (HAVE_WINDOWS_H) && defined (BFD_SUPPORTS_PLUGINS)

#define RTLD_LAZY 0      /* Dummy value.  */

static struct
{
  long lasterror;
  const char *err_rutin;
} var =
{
  0,
  NULL
};

static void *dlopen (const char *filename, int flags);
static void *dlsym (void *handle, const char *name);
static const char *dlerror (void);

static void *dlopen (const char *filename, int flags)
{
  (void)flags; // make compiler happy
  HINSTANCE hInst;

  hInst = LoadLibrary(filename);
  if (hInst==NULL)
    {
      var.lasterror = GetLastError ();
      var.err_rutin = "dlopen";
    }
  return hInst;
}

static void *dlsym (void *handle, const char *name)
{
  FARPROC fp;

  fp = GetProcAddress ((HINSTANCE)handle, name);
  if (!fp)
    {
      var.lasterror = GetLastError ();
      var.err_rutin = "dlsym";
    }
  return (void *)(intptr_t)fp;
}

static const char *dlerror (void)
{
  static char errstr [PATH_MAX];

  if (!var.lasterror)
    {
      return NULL;
    }

  snprintf (errstr, sizeof(errstr), "%s error #%ld", var.err_rutin,
            var.lasterror);
  return errstr;
}

#endif /* !defined (HAVE_DLFCN_H) && defined (_WIN32)  */

void *xtensa_load_config (const char *name ATTRIBUTE_UNUSED, void *def)
{
  static int init;
#if BFD_SUPPORTS_PLUGINS
  static void *handle;
  void *p;

  if (!init)
    {
      char *path = getenv ("XTENSA_GNU_CONFIG");

      init = 1;
      if (!path)
        return def;
      handle = dlopen (path, RTLD_LAZY);
      if (!handle)
        {
          fprintf (stderr,
                   "XTENSA_GNU_CONFIG is defined but could not be loaded: %s\n",
                   dlerror ());
          abort ();
        }
    }
  else if (!handle)
    {
      return def;
    }

  p = dlsym (handle, name);
  if (!p)
    {
      fprintf (stderr,
               "XTENSA_GNU_CONFIG is loaded but symbol \"%s\" is not found: %s\n",
               name, dlerror ());
      abort ();
    }
  return p;
#else /* BFD_SUPPORTS_PLUGINS  */
  if (!init)
    {
      char *path = getenv ("XTENSA_GNU_CONFIG");

      init = 1;
      if (path)
        {
          fprintf (stderr,
                   "XTENSA_GNU_CONFIG is defined but plugin support is disabled\n");
          abort ();
        }
    }
  return def;
#endif /* BFD_SUPPORTS_PLUGINS  */
}

struct xtensa_config *xtensa_get_config (int opt ATTRIBUTE_UNUSED)
{
  static struct xtensa_config *config;
  static struct xtensa_config xtensa_defconfig = XTENSA_CONFIG_INITIALIZER;

  if (!config)
    config = (struct xtensa_config *) xtensa_load_config ("xtensa_config",
             &xtensa_defconfig);

  if (config->config_size < sizeof(struct xtensa_config))
    {
      fprintf (stderr,
               "old or incompatible configuration is loaded: config_size = %lu, expected: %lu\n",
               (unsigned long) config->config_size,
               (unsigned long) sizeof (struct xtensa_config));
      abort ();
    }

  return config;
}
