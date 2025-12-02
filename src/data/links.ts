import GithubIcon from '../components/icons/GithubIcon.astro'
import LinkedinIcon from '../components/icons/LinkedinIcon.astro'

// ADD YOUR SOCIAL NETWORKS HERE
export const SOCIALNETWORKS = [
	{
		name: 'Github',
		url: 'https://github.com/sungpyocho',
		icon: GithubIcon
	},

	{
		name: 'LinkedIn',
		url: 'https://www.linkedin.com/in/sungpyo-cho/',
		icon: LinkedinIcon
	}
] as const
