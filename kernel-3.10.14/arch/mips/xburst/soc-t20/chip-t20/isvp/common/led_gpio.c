#include <linux/platform_device.h>
#include <linux/leds.h>
#include "board_base.h"

/* GPIO LED */
#if defined(CONFIG_LEDS_GPIO) || defined(CONFIG_LEDS_GPIO_MODULE)
struct gpio_led board_led[] = {
	{
		.name = "led_blue",
		.default_trigger = "mmc0",
		.gpio = 39,
		.active_low = 1,
	},
	{
		.name = "led_yellow",
		.default_trigger = "timer",
		.gpio = 38,
		.active_low = 1,
	},
	{
		.name = "led_blue1",
		.default_trigger = "mmc0",
		.gpio = 76,
		.active_low = 1,
	},
	{
		.name = "led_yellow1",
		.default_trigger = "timer",
		.gpio = 75,
		.active_low = 1,
	},
};

static struct gpio_led_platform_data board_led_data = {
	.num_leds	= ARRAY_SIZE(board_led),
	.leds		= board_led
};

struct platform_device jz_led_device = {
	.name		= "leds-gpio",
	.id		= -1,
	.dev		= {
	.platform_data	= &board_led_data,
	},
};
#endif /* CONFIG_LEDS_GPIO */
